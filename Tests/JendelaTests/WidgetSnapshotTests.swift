import XCTest
@testable import Jendela

/// The snapshot carries recent clipboard text so the widget can render it. The
/// clipboard store itself is encrypted, so this file should not be the one copy
/// of that text sitting readable next to it.
final class WidgetSnapshotTests: XCTestCase {
    func testSnapshotIsWrittenReadableOnlyByTheOwner() throws {
        var snapshot = WidgetSnapshot.placeholder
        snapshot.note = "permissions check \(UUID().uuidString)"
        XCTAssertTrue(SharedStore.save(snapshot), "nothing was written")

        let attributes: [FileAttributeKey: Any] = try FileManager.default.attributesOfItem(atPath: SharedStore.snapshotURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600, "snapshot is readable beyond its owner")
    }

    func testSaveSkipsAWriteWhenNothingChanged() {
        var snapshot = WidgetSnapshot.placeholder
        snapshot.note = "stable"
        _ = SharedStore.save(snapshot)
        XCTAssertFalse(SharedStore.save(snapshot),
                       "an unchanged snapshot should not be rewritten — it wakes the widget for nothing")
    }

    func testRoundTrip() {
        var snapshot = WidgetSnapshot.placeholder
        snapshot.note = "round trip"
        snapshot.themeName = "Ember Focus"
        snapshot.accentHex = 0xFF5A1F
        _ = SharedStore.save(snapshot)

        let loaded = SharedStore.load()
        XCTAssertEqual(loaded.note, "round trip")
        XCTAssertEqual(loaded.accentHex, 0xFF5A1F)
    }
}
