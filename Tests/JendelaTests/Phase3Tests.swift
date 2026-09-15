import AppKit
import EventKit
import XCTest
@testable import Jendela

final class MeetingTests: XCTestCase {
    @MainActor func testAccessStateIsHonest() {
        let meetings = Meetings()
        // Whatever the state, `needsPermission` must agree with it rather than
        // optimistically showing an empty day.
        XCTAssertEqual(meetings.needsPermission, meetings.access != .fullAccess)
        if meetings.needsPermission {
            XCTAssertTrue(meetings.upcoming.isEmpty, "must not claim an empty calendar without access")
        }
        print("CALENDAR ACCESS: \(meetings.access.rawValue) upcoming=\(meetings.upcoming.count)")
    }

    @MainActor func testWhenTextReadsSensibly() {
        let soon = Meetings.Meeting(
            id: "1", title: "Standup",
            start: Date().addingTimeInterval(600), end: Date().addingTimeInterval(1800),
            calendarColour: 0x336699, joinURL: nil, isAllDay: false
        )
        XCTAssertEqual(soon.whenText, "in 10m")
        XCTAssertFalse(soon.isNow)

        let running = Meetings.Meeting(
            id: "2", title: "Retro",
            start: Date().addingTimeInterval(-300), end: Date().addingTimeInterval(900),
            calendarColour: 0, joinURL: nil, isAllDay: false
        )
        XCTAssertTrue(running.isNow)
        XCTAssertTrue(running.whenText.hasPrefix("Now"))
    }
}

final class ClipboardPrivacyTests: XCTestCase {
    @MainActor func testExcludedAppIsNotRecorded() {
        let state = JendelaState()
        state.clipboardItems = []
        // Pretend whatever is frontmost right now is excluded.
        guard let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return  // no frontmost app in this runner
        }
        state.clipboardExcludedApps = [front]

        XCTAssertFalse(state.captureClipboardValue(text: "must-not-be-recorded", sourceBundleID: front), "copies from an excluded app must be ignored")
        XCTAssertTrue(state.clipboardItems.isEmpty)
    }

    @MainActor func testPlainTextPasteDropsFormatting() {
        let entry = ClipboardEntry(kind: .text, title: "hello world", subtitle: "t",
                                   data: Data("hello world".utf8), pasteboardType: .string)
        XCTAssertEqual(JendelaState.plainPasteText(for: entry), "hello world")
        let state = JendelaState()
        let board = NSPasteboard(name: .init("JendelaPlainPaste.\(UUID())"))
        defer { board.releaseGlobally() }
        state.pastePlain(entry, to: board)
        XCTAssertEqual(board.string(forType: .string), "hello world")
        XCTAssertNil(board.data(forType: .rtf), "no rich text should be written")
        XCTAssertNil(JendelaState.plainPasteText(for: ClipboardEntry(kind: .image, title: "image", subtitle: "t", data: nil, pasteboardType: nil)))
    }
}
