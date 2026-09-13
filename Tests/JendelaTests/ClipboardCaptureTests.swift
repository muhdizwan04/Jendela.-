import AppKit
import XCTest
@testable import Jendela

final class ClipboardCaptureTests: XCTestCase {
    @MainActor func testCopyIsCapturedAndPersisted() throws {
        ClipboardStore.wipe()
        let state = JendelaState()
        state.clipboardItems = []

        let secret = "jendela-capture-\(UUID().uuidString)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(secret, forType: .string)

        XCTAssertTrue(state.captureClipboardIfChanged(), "a fresh copy should be captured")
        XCTAssertEqual(state.clipboardItems.first?.title, secret)

        ClipboardStore.flush()
        let reloaded = ClipboardStore.load()
        XCTAssertEqual(reloaded.first?.title, secret, "capture must reach disk")
        ClipboardStore.wipe()
    }

    /// The store must fail loudly in tests rather than quietly dropping history.
    @MainActor func testSaveThenLoadIsNotEmpty() {
        ClipboardStore.wipe()
        let entry = ClipboardEntry(kind: .text, title: "abc", subtitle: "t",
                                   data: Data("abc".utf8), pasteboardType: .string)
        ClipboardStore.save([entry])
        ClipboardStore.flush()
        XCTAssertFalse(ClipboardStore.load().isEmpty, "saved history came back empty")
        ClipboardStore.wipe()
    }
}
