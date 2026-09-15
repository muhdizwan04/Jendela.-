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
        let menu = AppMenu.make()

        // Each of these must match a key equivalent, or the shortcut is dead.
        let expected: [(String, Selector)] = [
            ("v", #selector(NSText.paste(_:))),
            ("c", #selector(NSText.copy(_:))),
            ("x", #selector(NSText.cut(_:))),
            ("a", #selector(NSText.selectAll(_:))),
            ("z", Selector(("undo:"))),
        ]
        for (character, action) in expected {
            let item = menu.items.compactMap(\.submenu).flatMap(\.items).first {
                $0.keyEquivalent == character
                    && $0.keyEquivalentModifierMask.contains(.command)
                    && $0.action == action
            }
            XCTAssertNotNil(item, "⌘\(character.uppercased()) matched no menu item")
        }
    }

    /// An accessory app has no Dock tile and no Force Quit entry, so if its
    /// menu-bar icon is unreachable ⌘Q is the only way out.
    func testQuitHasAKeyEquivalent() {
        let menu = AppMenu.make()
        var found: NSMenuItem?
        for item in menu.items {
            for candidate in item.submenu?.items ?? []
            where candidate.keyEquivalent == "q" && candidate.keyEquivalentModifierMask == .command {
                found = candidate
            }
        }
        XCTAssertEqual(found?.action, #selector(NSApplication.terminate(_:)))
    }

    /// A bare SwiftPM executable has no bundle identifier. Matching on an empty
    /// one would make every development build terminate itself.
    func testInstanceGuardIgnoresABundlelessBuild() {
        if Bundle.main.bundleIdentifier?.isEmpty == false { return }
        XCTAssertFalse(AppMenu.yieldToRunningInstance())
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
