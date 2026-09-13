import AppKit
import XCTest
@testable import Jendela

/// The app is `LSUIElement`/`.accessory` and builds no menu of its own, so
/// AppKit supplies none. Standard editing shortcuts are delivered through
/// main-menu key equivalents, which is why ⌘V into the clipboard search, the
/// chat field or a note did nothing until `AppMenu` existed.
@MainActor
final class AppMenuTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // `NSApp` is nil inside a test bundle until an instance is created.
        _ = NSApplication.shared
        NSApp.mainMenu = nil
    }

    func testInstallProvidesTheStandardEditingShortcuts() {
        AppMenu.install()
        let menu = try? XCTUnwrap(NSApp.mainMenu)
        XCTAssertNotNil(menu)

        // Each of these must match a key equivalent, or the shortcut is dead.
        let expected: [(String, UInt16, NSEvent.ModifierFlags)] = [
            ("v", 0x09, .command),
            ("c", 0x08, .command),
            ("x", 0x07, .command),
            ("a", 0x00, .command),
            ("z", 0x06, .command),
        ]
        for (character, keyCode, flags) in expected {
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil,
                characters: character, charactersIgnoringModifiers: character,
                isARepeat: false, keyCode: keyCode)!
            XCTAssertTrue(NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false,
                          "⌘\(character.uppercased()) matched no menu item")
        }
    }

    func testInstallIsIdempotent() {
        AppMenu.install()
        let first = NSApp.mainMenu
        AppMenu.install()
        XCTAssertTrue(first === NSApp.mainMenu, "a second install replaced the menu")
    }

    /// A panel that cannot become key has no responder to route `paste:` to,
    /// so the menu match alone is not enough.
    func testNotchPanelCanBecomeKey() {
        let panel = InteractiveNotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        XCTAssertTrue(panel.canBecomeKey)
    }
}
