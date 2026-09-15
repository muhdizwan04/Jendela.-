import AppKit
import XCTest
@testable import Jendela

/// Phase 9: every feature exercised once, in order, looking for breakage.
/// Runs against a throwaway support directory so nothing real is touched.
final class WalkthroughTests: XCTestCase {

    // MARK: - Notch

    @MainActor func test01_NotchOpensClosesAndSizes() {
        let state = JendelaState()
        XCTAssertFalse(state.notchExpanded)

        state.openNotch()
        XCTAssertTrue(state.notchExpanded)
        XCTAssertFalse(state.notchPinned, "opening must not pin, or it can never auto-close")

        state.closeNotch()
        XCTAssertFalse(state.notchExpanded)

        state.toggleHub()
        XCTAssertTrue(state.notchExpanded)
        state.toggleHub()
        XCTAssertFalse(state.notchExpanded)
    }

    @MainActor func test02_EverySectionHasHeightAndContent() throws {
        guard let screen = NSScreen.main else { throw XCTSkip("No GUI screen in this test runner") }
        for section in JendelaState.NotchSection.allCases {
            let size = NotchMetrics.expandedSize(
                for: section, clipboardCount: 5, size: .standard, width: 438, shelfCount: 3
            )
            XCTAssertGreaterThan(size.height, NotchMetrics.chromeHeight,
                                 "\(section.rawValue) has no room for content")
            XCTAssertLessThan(size.height, screen.frame.height,
                              "\(section.rawValue) is taller than the screen")
            let frame = NotchMetrics.topAlignedFrame(size, on: screen)
            XCTAssertEqual(frame.maxY, screen.frame.maxY, accuracy: 1,
                           "\(section.rawValue) does not hang from the top")
        }
    }

    @MainActor func test03_SectionCustomisationKeepsAFloor() {
        let state = JendelaState()
        for section in JendelaState.NotchSection.allCases {
            state.setSection(section, enabled: false)
        }
        XCTAssertEqual(state.visibleSections.count, 1, "the hub must keep at least one tab")
        XCTAssertTrue(state.visibleSections.contains(state.selectedSection),
                      "the open tab must be one that is visible")
    }

    // MARK: - Clipboard

    @MainActor func test10_ClipboardCapturesEveryKind() {
        let state = JendelaState()
        state.clipboardItems = []
        state.clipboardExcludedApps = []

        XCTAssertTrue(state.captureClipboardValue(text: "walkthrough text"))
        XCTAssertEqual(state.clipboardItems.first?.kind, .text)

        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus(); NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4)); image.unlockFocus()
        XCTAssertTrue(state.captureClipboardValue(text: nil, imageData: image.tiffRepresentation))
        XCTAssertEqual(state.clipboardItems.first?.kind, .image)
    }

    @MainActor func test11_ClipboardDoesNotDuplicateOnPaste() {
        let state = JendelaState()
        state.clipboardItems = (1...4).map {
            ClipboardEntry(kind: .text, title: "item\($0)", subtitle: "t",
                           data: Data("item\($0)".utf8), pasteboardType: .string)
        }
        let third = state.clipboardItems[2]
        // The real write path, on a private pasteboard so the test cannot
        // clobber the clipboard of whoever is running it.
        let board = NSPasteboard(name: .init("JendelaWalkthrough.paste.\(UUID())"))
        defer { board.releaseGlobally() }
        state.pasteClipboard(third, to: board)
        XCTAssertEqual(state.clipboardItems.count, 4, "pasting must not add a duplicate")
        XCTAssertEqual(board.string(forType: .string), "item3",
                       "the chosen entry must reach the pasteboard")
        // The list deliberately does not reorder: rows must not jump out from
        // under the pointer in a hover-driven UI.
        XCTAssertEqual(state.clipboardItems[2].title, "item3")
    }

    @MainActor func test12_PinnedSurvivesTrimAndSearchFinds() {
        let state = JendelaState()
        state.clipboardItems = []
        var pinned = ClipboardEntry(kind: .text, title: "keep-me", subtitle: "t",
                                    data: Data("keep-me".utf8), pasteboardType: .string)
        pinned.pinned = true
        state.clipboardItems = [pinned]
        for i in 0..<200 {
            state.clipboardItems.append(ClipboardEntry(
                kind: .text, title: "filler\(i)", subtitle: "t",
                data: Data("filler\(i)".utf8), pasteboardType: .string))
        }
        let board = NSPasteboard(name: .init("JendelaWalkthrough.\(UUID())"))
        board.clearContents(); board.declareTypes([.string], owner: nil); board.setString("trim-trigger", forType: .string)
        _ = state.captureClipboardIfChanged(from: board)
        XCTAssertTrue(state.clipboardItems.contains { $0.pinned && $0.title == "keep-me" },
                      "a pinned entry was evicted")

        state.clipboardSearch = "keep-me"
        XCTAssertEqual(state.visibleClipboardItems.count, 1)
        state.clipboardSearch = ""
    }

    // MARK: - Notes

    @MainActor func test20_NotesAddDeleteAndPersist() {
        let state = JendelaState()
        let start = state.notes.count
        state.addNote()
        XCTAssertEqual(state.notes.count, start + 1)

        let id = state.notes.last!.id
        NoteStore.save(NSAttributedString(string: "walkthrough note",
                                          attributes: NoteStore.defaultAttributes), id: id)
        XCTAssertEqual(NoteStore.load(id).string, "walkthrough note")

        state.deleteNote(id)
        XCTAssertFalse(state.notes.contains { $0.id == id })
        XCTAssertEqual(NoteStore.load(id).string, "", "a deleted note's text must go too")
    }

    // MARK: - Shelf

    @MainActor func test30_ShelfHoldsAndForgets() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("walk-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("held.txt")
        try Data("x".utf8).write(to: file)

        ShelfStore.save([ShelfItem.make(file)])
        XCTAssertEqual(ShelfStore.load().count, 1)

        try FileManager.default.removeItem(at: file)
        XCTAssertEqual(ShelfStore.load().count, 0, "a vanished file must not linger on the shelf")
        ShelfStore.save([])
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Audio, power, batteries

    @MainActor func test40_SystemAudioReadsReality() {
        let audio = SystemAudio()
        XCTAssertTrue((0...1).contains(audio.volume), "volume out of range: \(audio.volume)")
        XCTAssertFalse(audio.currentDeviceName.isEmpty, "no output device name")
    }

    @MainActor func test41_PowerAndBatteryAgree() {
        let power = PowerMonitor()
        let batteries = Batteries()
        batteries.refresh()
        if let mac = batteries.mac {
            XCTAssertTrue((1...100).contains(mac.percent))
            // Both read the same power source, so they must not disagree.
            if mac.charging { XCTAssertFalse(power.onBattery, "charging but reported on battery") }
        }
    }

    // MARK: - Licensing

    @MainActor func test50_TrialGrantsEverythingThenGates() {
        Keychain.remove(account: "licence-key", service: "com.jendela.desktop")
        Keychain.remove(account: "trial-start", service: "com.jendela.desktop")

        let state = JendelaState()
        XCTAssertTrue(state.isPro, "a fresh install should be in trial")
        for section in JendelaState.NotchSection.allCases {
            XCTAssertFalse(state.requiresLicence(section), "trial should gate nothing")
        }

        // Expire the trial and check gating flips, but only for paid tabs.
        let old = Date().addingTimeInterval(-Double(Licensing.trialDays + 1) * 86400)
        Keychain.set(String(old.timeIntervalSince1970),
                     account: "trial-start", service: "com.jendela.desktop")
        state.licensing.refresh()
        XCTAssertFalse(state.isPro)
        // The clipboard is capped, not paywalled — the pricing page puts "Five
        // clipboard entries" on the free plan. Paywalling the tab made the cap
        // below unreachable.
        XCTAssertFalse(state.requiresLicence(.clipboard))
        XCTAssertEqual(state.effectiveClipboardLimit, 5)
        XCTAssertFalse(state.requiresLicence(.home), "free tabs must stay free")
        XCTAssertTrue(state.requiresLicence(.shelf), "paid tabs still need a licence")

        Keychain.remove(account: "trial-start", service: "com.jendela.desktop")
    }

    // MARK: - Widgets

    @MainActor func test60_WidgetSnapshotRoundTrips() {
        let snapshot = WidgetSnapshot(
            note: "hello", clips: [.init(id: "1", title: "c", kind: "text", pinned: false)],
            themeName: "Midnight Focus"
        )
        XCTAssertTrue(SharedStore.save(snapshot))
        let read = SharedStore.load()
        XCTAssertEqual(read.note, "hello")
        XCTAssertEqual(read.clips.count, 1)
        XCTAssertFalse(SharedStore.save(snapshot), "identical content should not trigger a reload")
    }

    // MARK: - Settings

    @MainActor func test70_SettingsRoundTripEveryField() {
        let state = JendelaState()
        state.hubWidth = 512
        state.clipboardLimit = 200
        state.ambientStyle = .artwork
        state.discordChannelName = "walkthrough"
        state.hotKeys[.clipboard] = HotKeyBinding(keyCode: 9, modifiers: 1 << 20, enabled: true)

        // Go through the real save/load path, not a bare encoder: the
        // forward-compatibility merge lives there.
        SettingsStore.save(state.settingsSnapshotForTesting())
        SettingsStore.flush()
        let decoded = SettingsStore.load()
        XCTAssertEqual(decoded.hubWidth, 512)
        XCTAssertEqual(decoded.clipboardLimit, 200)
        XCTAssertEqual(decoded.ambientStyle, "artwork")
        XCTAssertEqual(decoded.discordChannelName, "walkthrough")
        XCTAssertEqual(decoded.hotKeys["clipboard"]?.keyCode, 9)
    }
}

final class SettingsDriftTests: XCTestCase {
    /// Every field must survive save and load. A hand-written lenient decoder
    /// silently stopped covering new fields — hotKeys, hasOnboarded and
    /// clipboardExcludedApps were all being dropped — so this compares the
    /// whole struct rather than a sample of it.
    @MainActor func testEveryFieldSurvivesSaveAndLoad() {
        var settings = JendelaSettings()
        settings.quickNoteText = "drift"
        settings.hubWidth = 501
        settings.clipboardLimit = 175
        settings.clipboardExcludedApps = ["com.example.vault"]
        settings.hasOnboarded = true
        settings.launchAtLogin = true
        settings.hotKeys = ["clipboard": HotKeyBinding(keyCode: 9, modifiers: 1 << 20, enabled: true)]
        settings.notes = [NoteRecord(id: UUID(), frame: [1, 2, 300, 200])]
        settings.discordChannelName = "drift-room"
        settings.ambientStyle = "artwork"
        settings.musicIconStyle = "appIcon"
        settings.enabledSections = ["Home", "Clipboard"]

        SettingsStore.save(settings)
        SettingsStore.flush()
        XCTAssertEqual(SettingsStore.load(), settings, "a field was lost between save and load")
    }

    /// A file written by an older build has none of the newer keys.
    @MainActor func testOlderFileKeepsItsValuesAndDefaultsTheRest() throws {
        let old = #"{"quickNoteText":"from an old build","hubWidth":480}"#
        try Data(old.utf8).write(to: SettingsStore.fileURL)

        let loaded = SettingsStore.load()
        XCTAssertEqual(loaded.quickNoteText, "from an old build")
        XCTAssertEqual(loaded.hubWidth, 480)
        XCTAssertEqual(loaded.clipboardLimit, JendelaSettings().clipboardLimit)
        XCTAssertEqual(loaded.hasOnboarded, false)
    }
}
