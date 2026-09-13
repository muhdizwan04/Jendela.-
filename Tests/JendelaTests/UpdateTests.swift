import XCTest
@testable import Jendela

final class UpdateTests: XCTestCase {
    /// The classic version-comparison bug: as strings, "1.9" sorts after "1.10".
    @MainActor func testNumericVersionOrdering() {
        XCTAssertEqual(Updates.compare("1.10.0", "1.9.0"), .orderedDescending)
        XCTAssertEqual(Updates.compare("1.9.0", "1.10.0"), .orderedAscending)
        XCTAssertEqual(Updates.compare("2.0", "2.0.0"), .orderedSame)
        XCTAssertEqual(Updates.compare("0.2.0", "0.2.1"), .orderedAscending)
        XCTAssertEqual(Updates.compare("10.0", "9.99"), .orderedDescending)
    }

    @MainActor func testManifestParses() throws {
        let json = """
        {
          "version": "1.4.0",
          "build": 40,
          "url": "https://example.com/Jendela-1.4.0.dmg",
          "sha256": "abc",
          "minimumSystemVersion": "15.0",
          "publishedAt": "2026-01-02T03:04:05Z"
        }
        """.data(using: .utf8)!
        let release = try XCTUnwrap(Updates.parse(json))
        XCTAssertEqual(release.version, "1.4.0")
        XCTAssertEqual(release.build, 40)
        XCTAssertEqual(release.url.lastPathComponent, "Jendela-1.4.0.dmg")
        XCTAssertNotNil(release.publishedAt)
    }

    @MainActor func testGarbageManifestIsRejected() {
        XCTAssertNil(Updates.parse(Data("not json".utf8)))
        XCTAssertNil(Updates.parse(Data(#"{"version":"1.0"}"#.utf8)), "a manifest with no url is unusable")
    }

    /// Build number is authoritative when both sides have one, because marketing
    /// versions get re-cut while build numbers only ever climb.
    @MainActor func testBuildNumberDecidesWhenPresent() {
        let release = Updates.Release(
            version: "1.0.0", build: 41,
            url: URL(string: "https://example.com/x.dmg")!,
            notes: nil, minimumSystem: nil, publishedAt: nil
        )
        XCTAssertTrue(Updates.isNewer(release, thanVersion: "1.0.0", build: 40))
        XCTAssertFalse(Updates.isNewer(release, thanVersion: "1.0.0", build: 41))
        XCTAssertFalse(Updates.isNewer(release, thanVersion: "1.0.0", build: 99))
    }

    @MainActor func testFallsBackToVersionWhenNoBuild() {
        let release = Updates.Release(
            version: "1.2.0", build: 0,
            url: URL(string: "https://example.com/x.dmg")!,
            notes: nil, minimumSystem: nil, publishedAt: nil
        )
        XCTAssertTrue(Updates.isNewer(release, thanVersion: "1.1.9", build: 0))
        XCTAssertFalse(Updates.isNewer(release, thanVersion: "1.2.0", build: 0))
    }
}
