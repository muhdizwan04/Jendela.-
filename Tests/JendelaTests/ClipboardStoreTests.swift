import AppKit
import XCTest
@testable import Jendela

final class ClipboardStoreTests: XCTestCase {
    private func entry(_ title: String, kind: ClipboardEntry.Kind = .text,
                       bytes: Int = 4, pinned: Bool = false) -> ClipboardEntry {
        ClipboardEntry(
            kind: kind,
            title: title,
            subtitle: "test",
            data: Data(repeating: 7, count: bytes),
            pasteboardType: kind == .image ? .png : .string,
            pinned: pinned
        )
    }

    @MainActor func testHistorySurvivesARestart() {
        ClipboardStore.wipe()
        let written = [entry("first"), entry("second", pinned: true), entry("third")]
        ClipboardStore.save(written)
        ClipboardStore.flush()

        let read = ClipboardStore.load()
        XCTAssertEqual(read.map(\.title), ["first", "second", "third"])
        XCTAssertTrue(read[1].pinned, "pinned state must survive")
        XCTAssertEqual(read[0].data, Data(repeating: 7, count: 4))
        ClipboardStore.wipe()
    }

    /// The file must not be readable as plain text — a clipboard history in the
    /// clear would be the worst file this app could leave behind.
    @MainActor func testFileIsNotPlaintext() throws {
        ClipboardStore.wipe()
        ClipboardStore.save([entry("correct-horse-battery-staple")])
        ClipboardStore.flush()

        let raw = try Data(contentsOf: ClipboardStore.storageURL)
        XCTAssertFalse(
            raw.range(of: Data("correct-horse-battery-staple".utf8)) != nil,
            "secret text found verbatim in the stored file"
        )
        XCTAssertGreaterThan(raw.count, 16, "sealed box should carry nonce and tag")
        ClipboardStore.wipe()
    }

    /// Images are the only entries big enough to run away with the file size.
    @MainActor func testOlderImagesDropTheirBytes() {
        ClipboardStore.wipe()
        let images = (0..<(ClipboardStore.maxStoredImages + 5)).map {
            entry("img\($0)", kind: .image, bytes: 32)
        }
        ClipboardStore.save(images)
        ClipboardStore.flush()

        let read = ClipboardStore.load()
        XCTAssertEqual(read.count, images.count, "every image is still listed")
        XCTAssertNotNil(read.first?.data, "the newest keeps its bytes")
        XCTAssertNil(read.last?.data, "the oldest is listed without bytes")
        ClipboardStore.wipe()
    }

    @MainActor func testEntryCountIsCapped() {
        ClipboardStore.wipe()
        let many = (0..<(ClipboardStore.maxEntries + 40)).map { entry("e\($0)") }
        ClipboardStore.save(many)
        ClipboardStore.flush()
        XCTAssertEqual(ClipboardStore.load().count, ClipboardStore.maxEntries)
        ClipboardStore.wipe()
    }
}
