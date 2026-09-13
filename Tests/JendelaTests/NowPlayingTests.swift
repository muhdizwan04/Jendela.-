import AppKit
import XCTest
@testable import Jendela

/// YouTube Music's rich metadata arrives as four fields joined by the unit
/// separator — the page builds it with `String.fromCharCode(31)`.
@MainActor
final class NowPlayingTests: XCTestCase {
    private let separator = "\u{1F}"

    func testRichPayloadIsParsed() {
        let monitor = NowPlayingMonitor()
        let payload = ["Weightless", "Marconi Union", "", "1"].joined(separator: separator)

        monitor.applyYouTube(payload: payload)

        XCTAssertEqual(monitor.track?.title, "Weightless")
        XCTAssertEqual(monitor.track?.artist, "Marconi Union")
        XCTAssertEqual(monitor.track?.isPlaying, true)
        XCTAssertEqual(monitor.track?.source, .youtube)
    }

    func testPausedStateIsCarried() {
        let monitor = NowPlayingMonitor()
        monitor.applyYouTube(payload: ["Nightswimming", "R.E.M.", "", "0"].joined(separator: separator))
        XCTAssertEqual(monitor.track?.isPlaying, false, "a paused tab reported as playing")
    }

    /// The separator was previously the literal text `\u{1F}`, so a real
    /// payload split into one field and the track was cleared instead.
    func testALiteralEscapeIsNotTreatedAsTheSeparator() {
        let monitor = NowPlayingMonitor()
        monitor.applyYouTube(payload: #"Song\u{1F}Artist\u{1F}\u{1F}1"#)
        XCTAssertNil(monitor.track, "a payload with no real separator must not parse")
    }

    func testEmptyTitleClearsTheTrack() {
        let monitor = NowPlayingMonitor()
        monitor.applyYouTube(payload: ["Real", "Artist", "", "1"].joined(separator: separator))
        XCTAssertNotNil(monitor.track)
        monitor.applyYouTube(payload: ["", "", "", "0"].joined(separator: separator))
        XCTAssertNil(monitor.track)
    }
}
