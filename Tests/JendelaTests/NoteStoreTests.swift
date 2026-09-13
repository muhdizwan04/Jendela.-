import AppKit
import XCTest
@testable import Jendela

/// Note text lives in one RTF file per note. A launch that writes a note and
/// exits before its record is saved leaves that text behind, and nothing used
/// to collect it — so deleted or abandoned notes stayed readable on disk.
@MainActor
final class NoteStoreTests: XCTestCase {
    private func writeNote(_ id: UUID, _ text: String) {
        NoteStore.save(NSAttributedString(string: text, attributes: NoteStore.defaultAttributes), id: id)
    }

    override func setUp() {
        super.setUp()
        for file in (try? FileManager.default.contentsOfDirectory(
            at: NoteStore.directory, includingPropertiesForKeys: nil)) ?? []
        where file.lastPathComponent.hasPrefix("note-") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func testRichTextSurvivesARoundTrip() {
        let id = UUID()
        let text = NSMutableAttributedString(string: "bold and plain",
                                             attributes: NoteStore.defaultAttributes)
        text.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: NSRange(location: 0, length: 4))
        NoteStore.save(text, id: id)

        let loaded = NoteStore.load(id)
        XCTAssertEqual(loaded.string, "bold and plain")
        let font = loaded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false,
                      "bold did not survive the RTF round trip")
    }

    func testEmojiSurvive() {
        let id = UUID()
        writeNote(id, "café 🎧 ünïcode")
        XCTAssertEqual(NoteStore.load(id).string, "café 🎧 ünïcode")
    }

    func testNotesAreWrittenReadableOnlyByTheOwner() throws {
        let id = UUID()
        writeNote(id, "private")
        let attributes: [FileAttributeKey: Any] =
            try FileManager.default.attributesOfItem(atPath: NoteStore.url(for: id).path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testOrphanedNoteTextIsRemoved() throws {
        let kept = UUID(), orphan = UUID()
        writeNote(kept, "keep me")
        writeNote(orphan, "abandoned")
        // Pruning only runs off a settings file that was genuinely read.
        // Written directly: SettingsStore.save() is asynchronous, so saving and
        // immediately loading races the write.
        try JSONEncoder().encode(JendelaSettings()).write(to: SettingsStore.fileURL)
        _ = SettingsStore.load()
        XCTAssertTrue(SettingsStore.loadedFromDisk, "precondition: settings must have been read")

        NoteStore.pruneOrphans(keeping: [kept])

        XCTAssertTrue(FileManager.default.fileExists(atPath: NoteStore.url(for: kept).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: NoteStore.url(for: orphan).path),
                       "abandoned note text was left on disk")
    }

    /// The dangerous case: settings that cannot be read load as defaults, which
    /// would make every real note look orphaned.
    func testPruningIsSkippedWhenSettingsCouldNotBeRead() throws {
        let real = UUID()
        writeNote(real, "the user's actual note")
        try? FileManager.default.removeItem(at: SettingsStore.fileURL)
        _ = SettingsStore.load()          // no file — falls back to defaults

        NoteStore.pruneOrphans(keeping: [UUID()])

        XCTAssertTrue(FileManager.default.fileExists(atPath: NoteStore.url(for: real).path),
                      "a real note was deleted because settings were unreadable")
    }
}
