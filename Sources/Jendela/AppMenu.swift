import AppKit

/// The standard editing menu.
///
/// A menu-bar-only app (`LSUIElement`, `.accessory`) gets no main menu from
/// AppKit, and macOS delivers ⌘X, ⌘C, ⌘V, ⌘Z and ⌘A through main-menu key
/// equivalents — so without this, pasting into the clipboard search, the chat
/// field or a note silently does nothing. The menu is never displayed; it
/// exists purely so those keystrokes have somewhere to land.
enum AppMenu {
    static func install() {
        guard NSApp.mainMenu == nil else { return }

        let main = NSMenu()

        // An application menu has to exist for the ones after it to work.
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide Jendela.", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Jendela.", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        let entries: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            ("Undo", Selector(("undo:")), "z", .command),
            ("Redo", Selector(("redo:")), "z", [.command, .shift]),
            ("", Selector(("separator")), "", []),
            ("Cut", #selector(NSText.cut(_:)), "x", .command),
            ("Copy", #selector(NSText.copy(_:)), "c", .command),
            ("Paste", #selector(NSText.paste(_:)), "v", .command),
            ("Paste and Match Style", Selector(("pasteAsPlainText:")), "v", [.command, .option, .shift]),
            ("Delete", #selector(NSText.delete(_:)), "", []),
            ("Select All", #selector(NSText.selectAll(_:)), "a", .command),
        ]
        for (title, action, key, modifiers) in entries {
            if title.isEmpty {
                edit.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            edit.addItem(item)
        }
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    /// Hands over to an instance that is already running, and exits.
    ///
    /// Every instance adds its own menu-bar item. On a notched Mac the items
    /// that do not fit are hidden *behind* the notch rather than dropped, so a
    /// second copy can push the first one's icon somewhere unclickable — and
    /// with no Dock tile and no Force Quit entry, that leaves an app running
    /// with no way to quit it.
    ///
    /// Only enforced for a real bundle: a bare executable built by SwiftPM has
    /// no bundle identifier, and matching on an empty one would make every
    /// development build fight the last.
    static func yieldToRunningInstance() -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier, !identifier.isEmpty else { return false }
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != mine }
        guard let existing = others.first else { return false }
        existing.activate()
        return true
    }
}
