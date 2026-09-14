import AppIntents
import XCTest
@testable import Jendela

/// Shortcuts actions reach into the running app for their data. One that does
/// not bring the app up returns nothing at all when it happens not to be
/// running — in a Shortcut that is a wrong answer, not a visible failure.
@MainActor
final class IntentTests: XCTestCase {
    func testEveryIntentBringsTheAppUp() {
        XCTAssertTrue(OpenHubIntent.openAppWhenRun)
        XCTAssertTrue(OpenClipboardIntent.openAppWhenRun)
        XCTAssertTrue(NewNoteIntent.openAppWhenRun)
        XCTAssertTrue(ShowShelfIntent.openAppWhenRun)
        XCTAssertTrue(LatestClipboardIntent.openAppWhenRun,
                      "returns an empty string when the app is not running")
        XCTAssertTrue(StartFocusIntent.openAppWhenRun,
                      "silently does nothing when the app is not running")
    }

    /// The widget falls back to these before the app has ever written a
    /// snapshot, so they have to be the colours the app actually ships.
    func testSnapshotDefaultsMatchTheShippedTheme() {
        let theme = DesktopTheme.templates[0]
        let snapshot = WidgetSnapshot()
        XCTAssertEqual(snapshot.themeName, theme.name)
        XCTAssertEqual(snapshot.accentHex, theme.accentHex)
        XCTAssertEqual(snapshot.startHex, theme.startHex)
        XCTAssertEqual(snapshot.endHex, theme.endHex)
        XCTAssertEqual(snapshot.secondaryHex, theme.secondaryHex)
    }

    /// The action promises the copied text, and the history keeps it in full —
    /// only the display copy is clipped.
    func testLatestClipboardTextIsNotTruncated() {
        let state = JendelaState()
        let long = String(repeating: "a", count: 500)
        state.clipboardItems = [
            ClipboardEntry(kind: .text, title: long, subtitle: "Copied text",
                           data: nil, pasteboardType: .string)
        ]
        let entry = state.clipboardItems.first { $0.kind == .text }
        XCTAssertEqual(entry?.title.count, 500)
        XCTAssertLessThan(entry?.displayTitle.count ?? 0, 500, "displayTitle should be the clipped one")
    }
}
