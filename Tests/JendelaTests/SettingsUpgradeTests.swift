import XCTest
@testable import Jendela

final class SettingsUpgradeTests: XCTestCase {
    /// Older settings files do not have the newer keys. Swift's synthesised
    /// decoder throws on a missing key even when the property has a default, so
    /// without care every added setting silently resets everyone's preferences.
    ///
    /// The fix lives in `SettingsStore.load`, which merges the stored object
    /// over the defaults before decoding. That is deliberately *not* a
    /// hand-written lenient decoder: the first attempt was, and it silently
    /// stopped covering hotKeys, hasOnboarded and clipboardExcludedApps as soon
    /// as those were added.
    @MainActor func testOldSettingsFileStillLoads() throws {
        let old = #"{"quickNoteText":"keep me","appliedTemplateID":"aurora","hubWidth":512}"#
        try Data(old.utf8).write(to: SettingsStore.fileURL)

        let loaded = SettingsStore.load()
        XCTAssertEqual(loaded.quickNoteText, "keep me")
        XCTAssertEqual(loaded.hubWidth, 512)
        XCTAssertEqual(loaded.clipboardLimit, 100, "missing keys fall back to defaults")
        XCTAssertTrue(loaded.hotKeys.isEmpty)
    }

    /// A corrupt file must not take the app down with it.
    @MainActor func testCorruptFileFallsBackToDefaults() throws {
        try Data("this is not json".utf8).write(to: SettingsStore.fileURL)
        XCTAssertEqual(SettingsStore.load().hubWidth, JendelaSettings().hubWidth)
    }
}
