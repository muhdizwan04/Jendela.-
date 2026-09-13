import AppKit
import XCTest
@testable import Jendela

/// The overlay is built on `InteractiveNotchPanel`, which disables AppKit's own
/// frame constraining so the hub can sit in the menu bar. Everything built on
/// it therefore has to keep its own position honest: a frame saved on a display
/// that is later disconnected came back reported visible and drawn nowhere.
@MainActor
final class DiscordTests: XCTestCase {
    private var screen: NSRect { (NSScreen.main ?? NSScreen.screens[0]).visibleFrame }

    func testAFrameOnAVanishedDisplayIsBroughtBack() {
        let lost = NSRect(x: 5000, y: 3000, width: 300, height: 190)
        let corrected = lost.nudgedOntoScreen()
        XCTAssertTrue(NSScreen.screens.contains { $0.visibleFrame.intersects(corrected) },
                      "the overlay stayed off every display")
        XCTAssertEqual(corrected.width, 300, "size should be preserved when it fits")
        XCTAssertEqual(corrected.height, 190)
    }

    func testNegativeCoordinatesAreBroughtBack() {
        let corrected = NSRect(x: -4000, y: -2000, width: 300, height: 190).nudgedOntoScreen()
        XCTAssertTrue(NSScreen.screens.contains { $0.visibleFrame.intersects(corrected) })
    }

    func testAnOnScreenFrameIsLeftAlone() {
        let fine = NSRect(x: screen.midX, y: screen.midY, width: 300, height: 190)
        XCTAssertEqual(fine.nudgedOntoScreen(), fine, "a reachable window was moved for no reason")
    }

    /// Deliberately hanging a window off the edge is a normal thing to do, and
    /// should survive a relaunch.
    func testAPartlyOffScreenFrameIsLeftAlone() {
        let hanging = NSRect(x: screen.maxX - 200, y: screen.midY, width: 300, height: 190)
        XCTAssertEqual(hanging.nudgedOntoScreen(), hanging)
    }

    func testEveryDiscordBuildIsRecognised() {
        for id in ["com.hnc.Discord", "com.hnc.DiscordPTB",
                   "com.hnc.DiscordCanary", "com.hnc.DiscordDevelopment"] {
            XCTAssertTrue(JendelaState.discordBundleIDs.contains(id), "\(id) is not recognised")
        }
    }

    func testNoteFramesAreAlsoKeptReachable() {
        let record = NoteRecord(id: UUID(), frame: [9000, 9000, 330, 245])
        XCTAssertTrue(NSScreen.screens.contains { $0.visibleFrame.intersects(record.rect) },
                      "a note restored onto a vanished display is unreachable too")
    }
}
