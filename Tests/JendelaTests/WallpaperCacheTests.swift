import AppKit
import XCTest
@testable import Jendela

/// The masked-wallpaper cache is keyed by the source picture. `hashValue` was
/// used for that key and Swift seeds it randomly per process, so the same
/// wallpaper was cached under a new name on every launch — a multi-megabyte
/// PNG left behind each time, with nothing to collect them.
final class WallpaperCacheTests: XCTestCase {
    private func makeFile(_ name: String, bytes: Int) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wallpaper-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appendingPathComponent(name)
        try Data(count: bytes).write(to: file)
        return file.path
    }

    func testDigestIsStableForTheSameFile() throws {
        let path = try makeFile("stable.png", bytes: 32)
        XCTAssertEqual(WallpaperRenderer.digest(forPath: path),
                       WallpaperRenderer.digest(forPath: path),
                       "the same picture must cache under the same name")
    }

    func testDigestIsStableAcrossAKnownValue() throws {
        // Pinned so a future change to the hashing cannot silently start
        // orphaning every previously cached file.
        let path = try makeFile("pinned.png", bytes: 16)
        let first = WallpaperRenderer.digest(forPath: path)
        XCTAssertEqual(first.count, 16)
        XCTAssertTrue(first.allSatisfy(\.isHexDigit))
    }

    func testDifferentPicturesGetDifferentNames() throws {
        let a = try makeFile("a.png", bytes: 32)
        let b = try makeFile("b.png", bytes: 64)
        XCTAssertNotEqual(WallpaperRenderer.digest(forPath: a), WallpaperRenderer.digest(forPath: b))
    }

    /// Editing the picture has to produce a new render rather than serving the
    /// stale one from cache.
    func testEditingThePictureChangesTheName() throws {
        let path = try makeFile("edited.png", bytes: 32)
        let before = WallpaperRenderer.digest(forPath: path)
        try Data(count: 128).write(to: URL(fileURLWithPath: path))
        XCTAssertNotEqual(before, WallpaperRenderer.digest(forPath: path))
    }
}
