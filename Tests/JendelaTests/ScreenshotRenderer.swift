import AppKit
import SwiftUI
import XCTest
@testable import Jendela

/// Renders the hub to the PNGs the landing page ships.
///
/// The site's screenshots have to be regenerated whenever the app's colour or
/// layout changes, and taking them by hand means they quietly drift out of
/// date — the purple ones outlived the purple app by a whole redesign. This is
/// skipped unless `JENDELA_SHOTS` names an output directory, so it never runs
/// as part of an ordinary test pass.
@MainActor
final class ScreenshotRenderer: XCTestCase {
    func testRenderLandingPageScreenshots() throws {
        guard let directory = ProcessInfo.processInfo.environment["JENDELA_SHOTS"] else {
            throw XCTSkip("set JENDELA_SHOTS to a directory to regenerate the site's screenshots")
        }
        let out = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        for (section, name) in [(JendelaState.NotchSection.clipboard, "clipboard"),
                                (.home, "home"),
                                (.day, "day"),
                                (.shelf, "shelf"),
                                (.music, "music"),
                                (.sound, "sound")] {
            let state = Self.populated(section: section)
            let image = try XCTUnwrap(Self.render(state: state), "\(name) rendered nothing")
            let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image)
                .representation(using: .png, properties: [:]))
            try data.write(to: out.appendingPathComponent("\(name).png"))
            print("wrote \(name).png  \(image.width)x\(image.height)")
        }
    }

    /// A hub with enough in it to look like one in use rather than a fresh
    /// install — an empty clipboard makes a poor advertisement for a
    /// clipboard manager.
    private static func populated(section: JendelaState.NotchSection) -> JendelaState {
        // The shelf only keeps entries whose files still exist, so these have
        // to be real ones, written before the state loads them.
        seedShelf()
        let state = JendelaState()
        // Every test shares one support directory, so whatever another test
        // last persisted would otherwise decide the colour of these shots.
        state.appliedTemplateID = "midnight"
        state.hubWidth = 520
        state.selectedSection = section
        state.notchExpanded = true
        state.notchHovered = true
        state.clipboardItems = [
            ClipboardEntry(kind: .text, title: "compact row check one", subtitle: "Copied text",
                           data: nil, pasteboardType: .string),
            ClipboardEntry(kind: .text, title: "compact row check two", subtitle: "Copied text",
                           data: nil, pasteboardType: .string),
            ClipboardEntry(kind: .text, title: "https://jendela.app", subtitle: "Copied text",
                           data: nil, pasteboardType: .string),
            ClipboardEntry(kind: .file, title: "contract-final.pdf", subtitle: "Copied file",
                           data: nil, pasteboardType: nil),
            ClipboardEntry(kind: .image, title: "Screenshot 2026-09-13", subtitle: "1.2 MB",
                           data: nil, pasteboardType: nil),
            ClipboardEntry(kind: .text, title: "ssh deploy@jendela.app", subtitle: "Copied text",
                           data: nil, pasteboardType: .string, pinned: true)
        ]
        return state
    }

    private static func seedShelf() {
        let directory = SupportDirectory.root.appendingPathComponent("shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Real sizes: the shelf prints the file size, and a row of "1 byte"
        // makes the screenshot look like a mock-up.
        let files = [("press-kit.zip", 2_411_000), ("invoice-092.pdf", 184_000), ("cover.png", 1_130_000)]
        let items = files.map { name, bytes -> ShelfItem in
            let url = directory.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data(count: bytes))
            return ShelfItem.make(url)
        }
        ShelfStore.save(items)
    }

    /// Drawn through a real window rather than `ImageRenderer`.
    ///
    /// The hub contains a `TextField`, which is AppKit-backed on macOS:
    /// `ImageRenderer` cannot rasterise one and leaves a yellow placeholder
    /// where the clipboard search should be.
    private static func render(state: JendelaState) -> CGImage? {
        let host = NSHostingView(rootView: NotchPanelView(state: state).frame(width: state.hubWidth))
        // The same frame the live panel uses, so nothing sits flush against a
        // cut edge the way it does at the view's bare fitting size.
        host.frame = NSRect(origin: .zero, size: NotchMetrics.expandedSize(
            for: state.selectedSection,
            clipboardCount: state.visibleClipboardCount,
            size: state.notchSize,
            width: state.hubWidth,
            shelfCount: state.shelfItems.count))
        // A little air, so no section's last row sits flush against the cut.
        host.frame.size.height += 16

        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        window.backgroundColor = .clear
        window.isOpaque = false
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        // Give the field time to acquire its editor before the frame is taken.
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))

        let scale = 2
        let bounds = host.bounds
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width) * scale, pixelsHigh: Int(bounds.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = bounds.size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        host.displayIgnoringOpacity(bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()
        window.orderOut(nil)
        return rep.cgImage
    }
}
