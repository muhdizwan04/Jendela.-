import XCTest
@testable import Jendela

final class SettingsUpgradeTests: XCTestCase {
    /// Older settings files do not have the newer keys. Swift's synthesised
    /// decoder throws on a missing key even when the property has a default, so
    /// without care every added setting silently resets everyone's preferences.
    func testOldSettingsFileStillDecodes() throws {
        let old = """
        {"quickNoteText":"keep me","appliedTemplateID":"aurora","hubWidth":512}
        """.data(using: .utf8)!

        let decoded = try? JSONDecoder().decode(JendelaSettings.self, from: old)
        XCTAssertNotNil(decoded, "a settings file from an older build must still load")
        XCTAssertEqual(decoded?.quickNoteText, "keep me")
        XCTAssertEqual(decoded?.hubWidth, 512)
        XCTAssertEqual(decoded?.clipboardLimit, 100, "missing keys fall back to defaults")
    }
}
