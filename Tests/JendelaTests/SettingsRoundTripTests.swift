import AppKit
import XCTest
@testable import Jendela

/// Every setting must survive save → load. A field that `snapshot()` writes but
/// `apply()` never reads is invisible: the value is in the file, the app runs
/// with the default, and nothing reports a problem.
@MainActor
final class SettingsRoundTripTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: SettingsStore.fileURL)
    }

    func testEverySettingSurvivesSaveAndLoad() throws {
        let state = JendelaState()

        // Deliberately non-default values, so a field that is not read back
        // shows up as a difference rather than coincidentally matching.
        state.appliedTemplateID = "sage"
        state.selectedTemplateID = "ocean"
        state.expandOnHover = false
        state.showTrackInCompact = false
        state.showMusicIndicator = false
        state.clipboardAutoCapture = false
        state.skipConcealedClipboard = false
        state.clipboardLimit = 42
        state.clipboardExcludedApps = ["com.example.vault"]
        state.hasOnboarded = true
        state.musicProvider = .spotify
        state.discordPipEnabled = false
        state.noteVisible = true
        state.selectedSection = .shelf
        state.syncWallpaperWithTheme = true
        state.focusMinutes = 17
        state.showNotchHandle = true
        state.hubWidth = 511
        state.discordOverlayPinned = true
        state.discordOverlayOpacity = 0.61
        state.discordChannelName = "general"
        state.enabledSections = [.home, .clipboard]
        state.photoRotationMinutes = 11
        state.hotKeys[.notes] = HotKeyBinding(
            keyCode: 35, modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue, enabled: true)

        let saved = state.snapshot()
        SettingsStore.save(saved)

        let reloaded = JendelaState()
        let after = reloaded.snapshot()

        // `quickNoteText` is deliberately excluded: it mirrors the note's RTF
        // for the widget, and the RTF is the source of truth that overwrites it
        // on load. `hotKeys` is a dictionary, so its description ordering is
        // not stable — compare it directly instead.
        XCTAssertEqual(saved.hotKeys, after.hotKeys)

        // Compare field by field so a failure names the setting that was lost.
        let mirrorA = Mirror(reflecting: saved)
        let mirrorB = Mirror(reflecting: after)
        var lost: [String] = []
        for (a, b) in zip(mirrorA.children, mirrorB.children) {
            guard let label = a.label, label != "quickNoteText", label != "hotKeys" else { continue }
            if String(describing: a.value) != String(describing: b.value) {
                lost.append("\(label): saved \(a.value) but loaded \(b.value)")
            }
        }
        XCTAssertTrue(lost.isEmpty, "settings did not survive a round trip:\n  " + lost.joined(separator: "\n  "))
    }
}
