import AppKit
import SwiftUI
import XCTest
@testable import Jendela

/// Renders the Notch pane so its card alignment can be looked at rather than
/// assumed. Skipped unless JENDELA_SHOTS names a directory.
@MainActor
final class StudioLayoutRender: XCTestCase {
    func testRenderNotchStudio() throws {
        guard let directory = ProcessInfo.processInfo.environment["JENDELA_SHOTS"] else {
            throw XCTSkip("set JENDELA_SHOTS to render the studio pane")
        }
        let state = JendelaState()
        state.appliedTemplateID = "midnight"

        let host = NSHostingView(rootView:
            NotchStudioView(state: state)
                .frame(width: 1000)
                .background(Color(hex: 0x0D0D0F))
                .preferredColorScheme(.dark))
        host.frame = NSRect(origin: .zero, size: NSSize(width: 1000, height: host.fittingSize.height))

        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let scale = 2
        let bounds = host.bounds
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width) * scale, pixelsHigh: Int(bounds.height) * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = bounds.size
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        host.displayIgnoringOpacity(bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()
        window.orderOut(nil)

        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: directory).appendingPathComponent("studio-notch.png")
        try data.write(to: url)
        print("wrote \(url.path)  \(rep.pixelsWide)x\(rep.pixelsHigh)")
    }
}
