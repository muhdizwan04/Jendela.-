import AppKit
import SwiftUI
import XCTest
@testable import Jendela

/// A hub section is drawn into a card of a fixed height, and the card stops
/// growing after a few rows. A list longer than that was drawn straight past
/// the bottom of the hub and over the tab bar, with no way to reach it.
@MainActor
final class HubScrollTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        super.tearDown()
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        var found: [NSScrollView] = []
        if let scroll = view as? NSScrollView { found.append(scroll) }
        for sub in view.subviews { found += scrollViews(in: sub) }
        return found
    }

    private func mount<V: View>(_ view: V, height: CGFloat) -> NSView {
        let host = NSHostingView(rootView: view.frame(width: 420, height: height))
        host.frame = NSRect(x: 0, y: 0, width: 420, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        windows.append(window)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        return host
    }

    private func stateWithManyClips() -> JendelaState {
        let state = JendelaState()
        state.appliedTemplateID = "midnight"
        state.clipboardItems = (1...20).map {
            ClipboardEntry(kind: .text, title: "entry \($0)", subtitle: "Copied text",
                           data: nil, pasteboardType: .string)
        }
        return state
    }

    func testClipboardScrollsPastTheCardHeight() {
        let state = stateWithManyClips()
        let height = JendelaState.NotchSection.clipboard
            .contentHeight(clipboardCount: state.visibleClipboardCount)
        let view = mount(ClipboardNotchSection(state: state), height: height)
        XCTAssertFalse(scrollViews(in: view).isEmpty, "the clipboard list cannot be scrolled")
    }

    /// The card is capped, so twenty entries must not make it twenty rows tall.
    func testTheCardStopsGrowing() {
        let five = JendelaState.NotchSection.clipboard.contentHeight(clipboardCount: 5)
        let twenty = JendelaState.NotchSection.clipboard.contentHeight(clipboardCount: 20)
        XCTAssertEqual(JendelaState.NotchSection.clipboard.contentHeight(clipboardCount: 6), twenty)
        XCTAssertGreaterThan(twenty, five)
        XCTAssertLessThan(twenty, 400, "the hub would be taller than most of the screen")
    }

    /// Rows were 50pt apart; the request was for something more compact.
    func testRowsAreCompact() {
        let one = JendelaState.NotchSection.clipboard.contentHeight(clipboardCount: 1)
        let two = JendelaState.NotchSection.clipboard.contentHeight(clipboardCount: 2)
        XCTAssertLessThanOrEqual(two - one, 40, "rows grew rather than tightened")
    }

    func testShelfScrolls() {
        // The shelf only keeps entries whose files exist, and an empty shelf
        // shows a drop well rather than a list.
        let directory = SupportDirectory.root.appendingPathComponent("shelf-scroll", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let items = (1...12).map { index -> ShelfItem in
            let url = directory.appendingPathComponent("file-\(index).txt")
            FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
            return ShelfItem.make(url)
        }
        ShelfStore.save(items)

        let state = JendelaState()
        XCTAssertFalse(state.shelfItems.isEmpty, "precondition: the shelf must have files in it")
        let view = mount(ShelfNotchSection(state: state), height: 260)
        XCTAssertFalse(scrollViews(in: view).isEmpty, "the shelf cannot be scrolled")
    }

    func testDayScrolls() {
        let state = JendelaState()
        let view = mount(DayNotchSection(state: state), height: 208)
        XCTAssertFalse(scrollViews(in: view).isEmpty, "the day view cannot be scrolled")
    }
}
