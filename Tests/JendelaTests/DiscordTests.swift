import AppKit
import XCTest
@testable import Jendela

/// The overlay is built on `InteractiveNotchPanel`, which disables AppKit's own
/// frame constraining so the hub can sit in the menu bar. Everything built on
/// it therefore has to keep its own position honest: a frame saved on a display
/// that is later disconnected came back reported visible and drawn nowhere.
@MainActor
final class DiscordTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1512, height: 945)

    func testAFrameOnAVanishedDisplayIsBroughtBack() {
        let lost = NSRect(x: 5000, y: 3000, width: 300, height: 190)
        let corrected = lost.nudgedOntoScreen(in: [screen])
        XCTAssertTrue(screen.intersects(corrected),
                      "the overlay stayed off every display")
        XCTAssertEqual(corrected.width, 300, "size should be preserved when it fits")
        XCTAssertEqual(corrected.height, 190)
    }

    func testNegativeCoordinatesAreBroughtBack() {
        let corrected = NSRect(x: -4000, y: -2000, width: 300, height: 190).nudgedOntoScreen(in: [screen])
        XCTAssertTrue(screen.intersects(corrected))
    }

    func testAnOnScreenFrameIsLeftAlone() {
        let fine = NSRect(x: screen.midX, y: screen.midY, width: 300, height: 190)
        XCTAssertEqual(fine.nudgedOntoScreen(in: [screen]), fine, "a reachable window was moved for no reason")
    }

    /// Deliberately hanging a window off the edge is a normal thing to do, and
    /// should survive a relaunch.
    func testAPartlyOffScreenFrameIsLeftAlone() {
        let hanging = NSRect(x: screen.maxX - 200, y: screen.midY, width: 300, height: 190)
        XCTAssertEqual(hanging.nudgedOntoScreen(in: [screen]), hanging)
    }

    func testEveryDiscordBuildIsRecognised() {
        for id in ["com.hnc.Discord", "com.hnc.DiscordPTB",
                   "com.hnc.DiscordCanary", "com.hnc.DiscordDevelopment"] {
            XCTAssertTrue(JendelaState.discordBundleIDs.contains(id), "\(id) is not recognised")
        }
    }

    func testNoteFramesAreAlsoKeptReachable() {
        let saved = NSRect(x: 9000, y: 9000, width: 330, height: 245)
        XCTAssertTrue(screen.intersects(saved.nudgedOntoScreen(in: [screen])),
                      "a note restored onto a vanished display is unreachable too")
    }

    /// The tests above exercise the geometry on a fixed screen. This one checks
    /// a note is actually routed through it — a test of the helper alone would
    /// stay green if `NoteRecord.rect` stopped calling it.
    func testNoteRecordIsRoutedThroughTheScreenCheck() throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("No display in this test runner") }
        let record = NoteRecord(id: UUID(), frame: [9000, 9000, 330, 245])
        XCTAssertTrue(NSScreen.screens.contains { $0.visibleFrame.intersects(record.rect) },
                      "a note restored onto a vanished display is unreachable")
    }
}
