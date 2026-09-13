import AppKit
import XCTest
@testable import Jendela

final class HotKeyTests: XCTestCase {
    func testBindingNeedsAModifier() {
        // A bare key would swallow ordinary typing across the whole system.
        let bare = HotKeyBinding(keyCode: 9, modifiers: 0, enabled: true)
        XCTAssertFalse(bare.isValid)

        let withCommand = HotKeyBinding(
            keyCode: 9,
            modifiers: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue,
            enabled: true
        )
        XCTAssertTrue(withCommand.isValid)
        XCTAssertEqual(withCommand.display, "⇧⌘V")
    }

    func testDisabledBindingIsNotValid() {
        var binding = HotKeyAction.clipboard.defaultBinding
        binding.enabled = false
        XCTAssertFalse(binding.isValid)
    }

    func testBindingSurvivesEncoding() throws {
        let original = HotKeyAction.toggleHub.defaultBinding
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(HotKeyBinding.self, from: data), original)
    }

    /// The shipped defaults must not collide with something macOS already owns.
    @MainActor func testShippedDefaultsRegister() {
        let centre = HotKeyCenter.shared
        defer { centre.unregisterAll() }
        var bindings: [HotKeyAction: HotKeyBinding] = [:]
        for action in HotKeyAction.allCases { bindings[action] = action.defaultBinding }
        let failed = centre.apply(bindings) { _ in }
        XCTAssertTrue(failed.isEmpty, "default shortcuts refused by the system: \(failed.map(\.title))")
    }

    /// Registration must actually reach the system, not just be recorded.
    @MainActor func testRegistrationSucceeds() {
        let centre = HotKeyCenter.shared
        defer { centre.unregisterAll() }
        // F19: no default macOS binding, so this should not collide.
        let binding = HotKeyBinding(
            keyCode: 80,
            modifiers: NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.option.rawValue,
            enabled: true
        )
        let failed = centre.apply([.toggleHub: binding]) { _ in }
        XCTAssertTrue(failed.isEmpty, "the system refused a free combination: \(failed)")
    }
}

final class ShelfTests: XCTestCase {
    func testShelfRoundTripsAndDropsMissingFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jendela-shelf-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let present = dir.appendingPathComponent("kept.txt")
        try Data("hi".utf8).write(to: present)
        let missing = dir.appendingPathComponent("gone.txt")

        ShelfStore.save([ShelfItem.make(present), ShelfItem.make(missing)])
        let loaded = ShelfStore.load()

        XCTAssertEqual(loaded.count, 1, "a file that no longer exists must not linger")
        XCTAssertEqual(loaded.first?.name, "kept.txt")
        XCTAssertFalse(loaded.first!.sizeText.isEmpty)

        ShelfStore.save([])
        try? FileManager.default.removeItem(at: dir)
    }
}
