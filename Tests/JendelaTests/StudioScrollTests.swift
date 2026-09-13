import AppKit
import SwiftUI
import XCTest
@testable import Jendela

/// The Studio window is a fixed 1240x780 and each pane supplies its own
/// scrolling. Settings did not, so every control past the window height was
/// unreachable — no scrollbar, no wheel, nothing.
@MainActor
final class StudioScrollTests: XCTestCase {
    /// Height of the Studio window's content area, from `.defaultSize`.
    private let paneHeight: CGFloat = 780
    private let paneWidth: CGFloat = 1240 - 218   // window minus the sidebar

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        var found: [NSScrollView] = []
        if let scroll = view as? NSScrollView { found.append(scroll) }
        for sub in view.subviews { found += scrollViews(in: sub) }
        return found
    }

    /// Held so the windows outlive the assertions.
    private var windows: [NSWindow] = []

    /// A scroll view only lays its document out once it is in a window and the
    /// run loop has turned, so measuring it offscreen reports zero.
    private func host<V: View>(_ view: V) -> NSHostingView<some View> {
        let host = NSHostingView(rootView: view.frame(width: paneWidth, height: paneHeight))
        host.frame = NSRect(x: 0, y: 0, width: paneWidth, height: paneHeight)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        windows.append(window)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        return host
    }

    override func tearDown() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        super.tearDown()
    }

    func testSettingsPaneScrolls() {
        let state = JendelaState()
        let view = host(SettingsStudioView(state: state))
        let scrolls = scrollViews(in: view)
        XCTAssertFalse(scrolls.isEmpty, "the settings pane has no scroll view at all")

        // Content genuinely exceeds the window, so scrolling is not academic.
        let documentHeight = scrolls.map(\.documentView?.frame.height).compactMap { $0 }.max() ?? 0
        XCTAssertGreaterThan(documentHeight, paneHeight,
                             "settings content fits, so this test proves nothing — recheck it")
    }

    /// The others already scrolled; this keeps them that way.
    func testEveryStudioPaneScrolls() {
        let state = JendelaState()
        let panes: [(String, NSView)] = [
            ("Notch", host(NotchStudioView(state: state))),
            ("Widgets", host(WidgetLibraryView(state: state))),
            ("Photos", host(PhotoLibraryView(state: state))),
            ("Settings", host(SettingsStudioView(state: state))),
            ("Instructions", host(InstructionsStudioView(state: state)))
        ]
        for (name, view) in panes {
            XCTAssertFalse(scrollViews(in: view).isEmpty, "\(name) cannot scroll")
        }
    }
}
