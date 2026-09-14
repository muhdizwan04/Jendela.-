import AppKit
import XCTest
@testable import Jendela

/// Photo names are UUIDs when written, but they travel out through the settings
/// file and the shared snapshot and come back again, so a name is untrusted by
/// the time it is used to build a path.
final class PhotoStoreTests: XCTestCase {
    func testOrdinaryNamesResolve() {
        let url = PhotoStore.url(for: "0D1E2F30-0000-0000-0000-000000000000.jpg")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.deletingLastPathComponent().lastPathComponent, "Photos")
    }

    func testNamesThatEscapeTheDirectoryAreRefused() {
        for name in ["../secret.jpg", "../../../../etc/passwd", "sub/dir.jpg",
                     "..", ".", "", ".hidden", "a\\b.jpg"] {
            XCTAssertNil(PhotoStore.url(for: name), "accepted \(name)")
        }
    }

    func testRemoveIgnoresANameItWouldNotResolve() throws {
        // A file outside the photo directory must survive being named.
        let outside = SupportDirectory.root.appendingPathComponent("not-a-photo.txt")
        try Data("keep me".utf8).write(to: outside)

        PhotoStore.remove("../not-a-photo.txt")

        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path),
                      "a file outside the photo directory was deleted")
        try? FileManager.default.removeItem(at: outside)
    }

    func testExistingDropsUnresolvableNames() {
        XCTAssertEqual(PhotoStore.existing(["../x.jpg", "nope.jpg"]), [])
    }

    func testAddingAPhotoStoresItDownscaled() throws {
        // A picture wider than the longest edge kept on import.
        let size = NSSize(width: 3000, height: 1000)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.orange.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("wide.png")
        let rep = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: source)

        let name = try XCTUnwrap(PhotoStore.addPhoto(from: source), "the photo was not stored")
        let stored = try XCTUnwrap(PhotoStore.image(named: name))
        XCTAssertLessThanOrEqual(max(stored.size.width, stored.size.height), PhotoStore.maxEdge + 1,
                                 "the photo was stored at full size")
        PhotoStore.remove(name)
    }
}
