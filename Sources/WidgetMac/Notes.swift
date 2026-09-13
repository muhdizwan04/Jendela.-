import AppKit
import SwiftUI

/// The note's content and where it sits, kept beside the settings file.
///
/// Rich text is stored as RTF rather than folded into `settings.json`: it is
/// the format `NSTextView` reads and writes natively, so no conversion can lose
/// formatting, and it keeps a growing document out of the settings blob.
/// One sticky note: its own RTF file and its own place on the desktop.
struct NoteRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var frame: [Double]

    var rect: NSRect {
        frame.count == 4
            ? NSRect(x: frame[0], y: frame[1], width: max(frame[2], 180), height: max(frame[3], 120))
            : NoteRecord.defaultRect
    }

    static let defaultRect = NSRect(x: 72, y: 160, width: 330, height: 245)

    /// New notes cascade so a fresh one never lands exactly on the last.
    static func next(after existing: [NoteRecord]) -> NoteRecord {
        let step = CGFloat(existing.count % 8) * 26
        let base = defaultRect
        return NoteRecord(
            id: UUID(),
            frame: [base.minX + step, base.minY - step, base.width, base.height]
        )
    }
}

enum NoteStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WidgetMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// The pre-multi-note file, kept only so an existing note can be migrated.
    static var fileURL: URL { directory.appendingPathComponent("note.rtf") }

    static func url(for id: UUID) -> URL {
        directory.appendingPathComponent("note-\(id.uuidString).rtf")
    }

    static func load(_ id: UUID) -> NSAttributedString {
        guard let data = try? Data(contentsOf: url(for: id)),
              let text = NSAttributedString(rtf: data, documentAttributes: nil)
        else { return NSAttributedString(string: "", attributes: defaultAttributes) }
        return text
    }

    static func save(_ text: NSAttributedString, id: UUID) {
        let range = NSRange(location: 0, length: text.length)
        guard let data = text.rtf(from: range, documentAttributes: [:]) else { return }
        try? data.write(to: url(for: id), options: .atomic)
    }

    static func remove(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    static func load() -> NSAttributedString {
        guard let data = try? Data(contentsOf: fileURL),
              let text = NSAttributedString(rtf: data, documentAttributes: nil)
        else { return NSAttributedString(string: "", attributes: defaultAttributes) }
        return text
    }

    static func save(_ text: NSAttributedString) {
        let range = NSRange(location: 0, length: text.length)
        guard let data = text.rtf(from: range, documentAttributes: [:]) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static var defaultAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.white
        ]
    }
}

/// An `NSTextView` with a note-specific context menu.
///
/// SwiftUI's `TextEditor` is plain text only, so rich formatting has to come
/// from AppKit. The formatting actions here are the standard responder ones
/// where they exist (`underline:`, `alignLeft:`) and font-trait edits where
/// they do not — AppKit has no `toggleBold:`.
final class NoteTextView: NSTextView {
    var onClear: (() -> Void)?
    var onHide: (() -> Void)?
    var onNew: (() -> Void)?
    var onDelete: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()

        menu.addItem(withTitle: "Cut", action: #selector(cut(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        let style = NSMenu()
        style.addItem(item("Bold", #selector(noteBold(_:)), "b"))
        style.addItem(item("Italic", #selector(noteItalic(_:)), "i"))
        style.addItem(item("Underline", #selector(underline(_:)), "u"))
        style.addItem(.separator())
        style.addItem(item("Bigger", #selector(noteBigger(_:)), "+"))
        style.addItem(item("Smaller", #selector(noteSmaller(_:)), "-"))
        let styleItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        styleItem.submenu = style
        menu.addItem(styleItem)

        let align = NSMenu()
        align.addItem(item("Left", #selector(alignLeft(_:)), ""))
        align.addItem(item("Centre", #selector(alignCenter(_:)), ""))
        align.addItem(item("Right", #selector(alignRight(_:)), ""))
        align.addItem(item("Justify", #selector(alignJustified(_:)), ""))
        let alignItem = NSMenuItem(title: "Alignment", action: nil, keyEquivalent: "")
        alignItem.submenu = align
        menu.addItem(alignItem)

        menu.addItem(.separator())
        menu.addItem(item("New Note", #selector(noteNew(_:)), "n"))
        menu.addItem(item("Clear Note", #selector(noteClear(_:)), ""))
        menu.addItem(item("Hide Note", #selector(noteHide(_:)), ""))
        menu.addItem(.separator())
        menu.addItem(item("Delete Note", #selector(noteDelete(_:)), ""))
        return menu
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    // MARK: - Formatting

    @objc func noteBold(_ sender: Any?) { toggle(.boldFontMask) }
    @objc func noteItalic(_ sender: Any?) { toggle(.italicFontMask) }
    @objc func noteBigger(_ sender: Any?) { resize(by: 1) }
    @objc func noteSmaller(_ sender: Any?) { resize(by: -1) }

    @objc func noteClear(_ sender: Any?) {
        let whole = NSRange(location: 0, length: textStorage?.length ?? 0)
        guard shouldChangeText(in: whole, replacementString: "") else { return }
        textStorage?.setAttributedString(NSAttributedString(string: "", attributes: NoteStore.defaultAttributes))
        didChangeText()
        onClear?()
    }

    @objc func noteHide(_ sender: Any?) { onHide?() }
    @objc func noteNew(_ sender: Any?) { onNew?() }

    @objc func noteDelete(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Delete this note?"
        alert.informativeText = "Its text is removed for good."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        onDelete?()
    }

    /// ⌘B / ⌘I / ⌘U while typing, not just from the menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": noteBold(nil); return true
        case "i": noteItalic(nil); return true
        case "u": underline(nil); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }

    private func toggle(_ trait: NSFontTraitMask) {
        let manager = NSFontManager.shared
        let range = selectedRange()

        guard range.length > 0 else {
            // Nothing selected: change what the next keystrokes will look like.
            let font = (typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 14)
            let has = manager.traits(of: font).contains(trait)
            typingAttributes[.font] = has
                ? manager.convert(font, toNotHaveTrait: trait)
                : manager.convert(font, toHaveTrait: trait)
            return
        }

        guard let storage = textStorage, shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, sub, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 14)
            let has = manager.traits(of: font).contains(trait)
            storage.addAttribute(
                .font,
                value: has ? manager.convert(font, toNotHaveTrait: trait)
                           : manager.convert(font, toHaveTrait: trait),
                range: sub
            )
        }
        storage.endEditing()
        didChangeText()
    }

    private func resize(by delta: CGFloat) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage,
              shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, sub, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 14)
            let size = min(max(font.pointSize + delta, 9), 48)
            storage.addAttribute(.font, value: NSFont(descriptor: font.fontDescriptor, size: size) ?? font, range: sub)
        }
        storage.endEditing()
        didChangeText()
    }
}

/// Bridges the AppKit text view into SwiftUI.
struct RichNoteEditor: NSViewRepresentable {
    let id: UUID
    var onChange: (NSAttributedString) -> Void
    var onHide: () -> Void
    var onNew: () -> Void
    var onDelete: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(id: id, onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let text = NoteTextView(frame: .zero)
        text.delegate = context.coordinator
        text.isRichText = true
        text.allowsUndo = true
        text.isEditable = true
        text.isSelectable = true
        text.drawsBackground = false
        text.textColor = .white
        text.insertionPointColor = .white
        text.font = NSFont.systemFont(ofSize: 14)
        text.typingAttributes = NoteStore.defaultAttributes
        text.textContainerInset = NSSize(width: 6, height: 10)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textStorage?.setAttributedString(NoteStore.load(id))
        text.onHide = onHide
        text.onNew = onNew
        text.onDelete = onDelete

        let scroll = NSScrollView()
        scroll.documentView = text
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let id: UUID
        private let onChange: (NSAttributedString) -> Void
        private var saveWork: DispatchWorkItem?

        init(id: UUID, onChange: @escaping (NSAttributedString) -> Void) {
            self.id = id
            self.onChange = onChange
        }

        /// Debounced: typing should not write a file on every keystroke.
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView,
                  let storage = view.textStorage else { return }
            let snapshot = NSAttributedString(attributedString: storage)
            saveWork?.cancel()
            let work = DispatchWorkItem { [id, onChange] in
                NoteStore.save(snapshot, id: id)
                onChange(snapshot)
            }
            saveWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }
}
