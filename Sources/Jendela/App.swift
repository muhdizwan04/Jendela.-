import AppKit
import Combine
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

struct DesktopTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    let subtitle: String
    let startHex: UInt32
    let endHex: UInt32
    let accentHex: UInt32
    let secondaryHex: UInt32

    static func components(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    var startColor: Color { Color(hex: startHex) }
    var endColor: Color { Color(hex: endHex) }
    var accentColor: Color { Color(hex: accentHex) }
    var secondaryColor: Color { Color(hex: secondaryHex) }

    static let templates: [DesktopTheme] = [
        DesktopTheme(id: "midnight", name: "Midnight Focus", category: "Dark", subtitle: "Deep violet · calm workspace", startHex: 0x1D2B4A, endHex: 0x321432, accentHex: 0xA379FF, secondaryHex: 0xE36A96),
        DesktopTheme(id: "blush", name: "Blush Studio", category: "Cozy", subtitle: "Warm pink · soft cream", startHex: 0x7B2945, endHex: 0xD98E91, accentHex: 0xFF8FB5, secondaryHex: 0xFFE0D5),
        DesktopTheme(id: "aurora", name: "Aurora Glass", category: "Featured", subtitle: "Ocean teal · northern glow", startHex: 0x073C49, endHex: 0x17666F, accentHex: 0x65E6D2, secondaryHex: 0xA8F0FF),
        DesktopTheme(id: "linen", name: "Quiet Linen", category: "Minimal", subtitle: "Warm ivory · editorial", startHex: 0xA08A72, endHex: 0xDED0B9, accentHex: 0xFFF2D8, secondaryHex: 0x6C5848),
        DesktopTheme(id: "sage", name: "Sage Study", category: "Study", subtitle: "Muted green · focused", startHex: 0x365348, endHex: 0x829B72, accentHex: 0xC6E6B2, secondaryHex: 0xF1E8D5),
        DesktopTheme(id: "mono", name: "Mono Space", category: "Minimal", subtitle: "Graphite · monochrome", startHex: 0x111318, endHex: 0x3B3E46, accentHex: 0xF4F4F5, secondaryHex: 0x9B9CA3),
        DesktopTheme(id: "sunset", name: "Sunset Desk", category: "Cozy", subtitle: "Amber · rose dusk", startHex: 0x7D244A, endHex: 0xD76D3A, accentHex: 0xFFC76A, secondaryHex: 0xFF8AA5),
        DesktopTheme(id: "ocean", name: "Ocean Notes", category: "Study", subtitle: "Indigo · coastal blue", startHex: 0x163A63, endHex: 0x317A83, accentHex: 0x79D8E6, secondaryHex: 0xB7C9FF)
    ]
}

enum MusicProvider: String, CaseIterable, Identifiable {
    case appleMusic = "Music"
    case spotify = "Spotify"
    case youtube = "YouTube Music"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .appleMusic: "music.note"
        case .spotify: "circle.fill"
        case .youtube: "play.rectangle.fill"
        }
    }
}

struct ClipboardEntry: Identifiable {
    enum Kind: String {
        case text, image, file
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let subtitle: String
    let data: Data?
    let pasteboardType: NSPasteboard.PasteboardType?
    var pinned = false

    var symbol: String {
        switch kind {
        case .text: "doc.text"
        case .image: "photo"
        case .file: "doc"
        }
    }

    var fingerprint: String {
        if let data { return "\(kind.rawValue)|\(data.count)|\(data.hashValue)" }
        return "\(kind.rawValue)|\(title)"
    }

    var kindLabel: String {
        switch kind {
        case .text: "TEXT"
        case .image: "IMAGE"
        case .file: "FILE"
        }
    }

    /// Display text, clipped so a multi-megabyte copy never reaches a `Text`.
    var displayTitle: String {
        title.count > 200 ? String(title.prefix(200)) + "…" : title
    }
}

@MainActor
final class JendelaState: ObservableObject {
    enum NotchSize: String, CaseIterable, Identifiable {
        case compact = "Compact"
        case standard = "Standard"
        case wide = "Wide"

        var id: String { rawValue }
        var expandedWidth: CGFloat {
            switch self {
            case .compact: 390
            case .standard: 438
            case .wide: 486
            }
        }
    }

    enum StudioSection: String, CaseIterable, Identifiable {
        case notch = "Notch Hub"
        case widgets = "Widgets"
        case photos = "Photos"
        case settings = "Settings"
        case instructions = "Instructions"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .notch: "rectangle.topthird.inset.filled"
            case .widgets: "square.grid.2x2"
            case .photos: "photo.on.rectangle.angled"
            case .settings: "slider.horizontal.3"
            case .instructions: "book.closed"
            }
        }
    }

    enum NotchSection: String, CaseIterable, Identifiable {
        case home = "Home"
        case clipboard = "Clipboard"
        case music = "Music"
        case sound = "Sound"
        case discord = "Discord"
        case ai = "AI"
        case shelf = "Shelf"
        case day = "Day"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .home: "sparkles"
            case .clipboard: "doc.on.clipboard"
            case .music: "music.note"
            case .sound: "speaker.wave.2"
            case .discord: "bubble.left.and.bubble.right.fill"
            case .ai: "sparkle.magnifyingglass"
            case .shelf: "tray.full"
            case .day: "calendar.day.timeline.left"
            case .shelf: "tray.full"
            }
        }

        /// Natural height of this section's content at the expanded width,
        /// measured from the rendered views. Clipboard grows with its rows
        /// (header + hint = 47, then 38pt rows on 8pt spacing).
        func contentHeight(clipboardCount: Int, shelfCount: Int = 0) -> CGFloat {
            switch self {
            case .home: 157
            case .clipboard: 98 + 50 * CGFloat(min(max(clipboardCount, 1), 5))
            case .music: 141
            case .sound: 190
            case .discord: 214
            case .ai: 370
            case .shelf: 96 + 50 * CGFloat(min(max(shelfCount, 1), 5))
            case .day: 208
            }
        }
    }

    // MARK: - Published state

    @Published var notchExpanded = false
    @Published var notchHovered = false
    /// Which sections appear in the hub. Empty means "all".
    @Published var enabledSections: [NotchSection] = NotchSection.allCases
    var dismissNotch: (() -> Void)?
    /// Raises the desktop note above other windows; it drops back to desktop
    /// level on its own once it loses focus.
    var raiseNote: ((UUID?) -> Void)?
    var pointerAtNotch: ((Bool) -> Void)?

    /// Opening never pins. Pinning is an explicit act (the pin button, or the
    /// AI tab while you are typing) — otherwise a click-to-open left the hub
    /// pinned forever and it would never close when the pointer left.
    func openNotch(_ section: NotchSection? = nil, pinned: Bool = false) {
        if let section { selectedSection = section }
        notchPinned = pinned
        notchExpanded = true
    }

    func closeNotch() {
        notchPinned = false
        notchExpanded = false
        dismissNotch?()
    }

    func toggleHub() {
        if notchExpanded { closeNotch() } else { openNotch() }
    }
    @Published var notchPinned = false
    @Published var notchSize: NotchSize = .standard
    @Published var expandOnHover = true
    @Published var showTrackInCompact = true
    @Published var showMusicIndicator = true
    @Published var ambientStyle: AmbientStyle = .waveform
    @Published var musicIconStyle: MusicIconStyle = .automatic
    /// Bumped after importing a custom icon so the views reload it.
    @Published private(set) var musicIconVersion = 0
    /// Width of the expanded hub, adjustable rather than three fixed presets.
    @Published var hubWidth: Double = 438
    /// Where the note sits and how big it is, so it stays put between launches.
    /// Every sticky note on the desktop. There is always at least one, so
    /// "Notes" in the hub never opens onto nothing.
    @Published var notes: [NoteRecord] = [NoteRecord.next(after: [])]
    @Published var discordOverlayFrame = NSRect(x: 900, y: 620, width: 300, height: 190)
    /// Keeps the overlay up with no call, for positioning or as a reminder.
    @Published var discordOverlayPinned = false
    @Published var discordOverlayOpacity: Double = 0.94
    /// Free text: without Discord's RPC there is no way to read the real
    /// channel name, so the label is the user's to set.
    @Published var discordChannelName = ""
    /// True while the chat field has keyboard focus; holds the hub open so
    /// typing is not interrupted, without pinning it permanently.
    @Published var chatFocused = false
    /// When the chat field last received a keystroke.
    private var lastChatKeystroke = Date.distantPast

    func noteChatActivity() { lastChatKeystroke = .now }

    /// Registers the current set and records any the system refused.
    func applyHotKeys() {
        let failed = HotKeyCenter.shared.apply(hotKeys) { [weak self] action in
            self?.perform(action)
        }
        rejectedHotKeys = Set(failed)
    }

    func perform(_ action: HotKeyAction) {
        switch action {
        case .toggleHub:
            toggleHub()
        case .clipboard:
            openNotch(.clipboard)
        case .ai:
            openNotch(.ai)
        case .shelf:
            openNotch(.shelf)
        case .notes:
            showNotes()
        }
    }

    func setHotKey(_ action: HotKeyAction, to binding: HotKeyBinding) {
        hotKeys[action] = binding
    }

    enum AmbientStyle: String, CaseIterable, Identifiable {
        case waveform, artwork, title, none

        var id: String { rawValue }
        var label: String {
            switch self {
            case .waveform: "Waveform"
            case .artwork: "Album art"
            case .title: "Track name"
            case .none: "Nothing"
            }
        }
        var detail: String {
            switch self {
            case .waveform: "A small pulsing bar graph"
            case .artwork: "Cover art in a circle"
            case .title: "The track name in a pill"
            case .none: "Keep the menu bar clear"
            }
        }
    }
    @Published var selectedSection: NotchSection = .home
    @Published var quickNoteText = ""
    @Published var clipboardItems: [ClipboardEntry] = [] {
        didSet { if loaded { ClipboardStore.save(clipboardItems) } }
    }
    /// How many unpinned items to keep. Pinned entries are never evicted.
    @Published var clipboardLimit = 100
    @Published var hotKeys: [HotKeyAction: HotKeyBinding] = [:] {
        didSet { if loaded { applyHotKeys() } }
    }
    /// Combinations another app already owns, so the UI can say so.
    @Published private(set) var rejectedHotKeys: Set<HotKeyAction> = []

    @Published private(set) var shelfItems: [ShelfItem] = []
    @Published var needsOnboarding = false

    func finishOnboarding() {
        needsOnboarding = false
        hasOnboarded = true
    }

    func addToShelf(from providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { [weak self] in
                        guard let self, !self.shelfItems.contains(where: { $0.path == url.path }) else { return }
                        self.shelfItems.insert(ShelfItem.make(url), at: 0)
                        ShelfStore.save(self.shelfItems)
                    }
                }
            }
        }
    }

    func removeFromShelf(_ item: ShelfItem) {
        shelfItems.removeAll { $0.id == item.id }
        ShelfStore.save(shelfItems)
    }

    func clearShelf() {
        shelfItems = []
        ShelfStore.save(shelfItems)
    }

    /// Set once the introduction has been seen, so it never returns.
    @Published var hasOnboarded = false

    @Published var launchAtLogin = false {
        didSet {
            guard loaded, launchAtLogin != LoginItem.isEnabled else { return }
            if !LoginItem.set(launchAtLogin) { launchAtLogin = LoginItem.isEnabled }
        }
    }
    @Published var clipboardSearch = ""
    @Published var clipboardAutoCapture = true
    /// Password managers flag their pasteboard items as concealed; honouring
    /// that keeps credentials out of the history entirely.
    @Published var skipConcealedClipboard = true
    /// Bundle identifiers whose copies are never recorded. Useful for password
    /// managers that do not mark their pasteboard items as concealed, and for
    /// anything else you would rather not have a history of.
    @Published var clipboardExcludedApps: [String] = []
    @Published var musicProvider: MusicProvider = .appleMusic
    @Published var focusMinutes = 25
    @Published private(set) var focusRemaining = 0
    @Published private(set) var focusRunning = false
    @Published var discordCameraOn = false
    @Published var discordSharingOn = false
    @Published var discordPipEnabled = true
    @Published private(set) var discordRunning = false
    @Published var batterySaverMode: BatterySaverMode = .auto
    @Published var syncWallpaperWithTheme = false
    @Published private(set) var wallpaperError: String?
    /// Drives the panel height, so filtering the list resizes the hub.
    @Published private(set) var visibleClipboardCount = 0
    /// Set when YouTube Music control is asked for without Accessibility access.
    @Published var needsAccessibility = false
    /// Off by default: the collapsed hub is invisible until hovered, so nothing
    /// is drawn on the desktop while it is idle.
    @Published var showNotchHandle = false
    /// TopNotch-style: black out the menu-bar strip in the desktop picture so
    /// the notch blends into it.
    @Published var hideNotch = false
    @Published var photos: [String] = []
    @Published var photoRotationMinutes = 30
    /// The user's own wallpaper per screen, so the mask can be undone.
    private var originalWallpapers: [String] = []
    @Published var noteVisible = false
    @Published var studioSection: StudioSection = .notch
    @Published var selectedCategory = "All"
    @Published var templateSearch = ""
    @Published var selectedTemplateID = "midnight"
    @Published var appliedTemplateID = "midnight"

    // MARK: - Subsystems

    let quickChat = QuickChatClient()
    let power = PowerMonitor()
    let nowPlaying = NowPlayingMonitor()
    let audio = SystemAudio()
    let batteries = Batteries()
    let meetings = Meetings()
    let licensing = Licensing()

    private var cancellables = Set<AnyCancellable>()
    private var focusTimer: Timer?
    private var loaded = false
    private var lastSavedSettings: JendelaSettings?
    private var lastPublishedSnapshot: WidgetSnapshot?

    enum BatterySaverMode: String, CaseIterable, Identifiable {
        case auto, on, off
        var id: String { rawValue }
        var label: String {
            switch self {
            case .auto: "Automatic"
            case .on: "Always on"
            case .off: "Off"
            }
        }
    }

    init() {
        apply(SettingsStore.load())

        // The note used to be plain text inside settings.json. Seed the RTF
        // file from it once, so an existing note survives the move to rich text
        // instead of looking like it was wiped.
        if let first = notes.first {
            let target = NoteStore.url(for: first.id)
            if !FileManager.default.fileExists(atPath: target.path) {
                // Seed from the single-note file, or from the older plain text.
                if FileManager.default.fileExists(atPath: NoteStore.fileURL.path) {
                    NoteStore.save(NoteStore.load(), id: first.id)
                } else if !quickNoteText.isEmpty {
                    NoteStore.save(
                        NSAttributedString(string: quickNoteText, attributes: NoteStore.defaultAttributes),
                        id: first.id
                    )
                }
            }
            // RTF is the source of truth; the plain string feeds the widget.
            quickNoteText = NoteStore.load(first.id).string
        }

        // Loaded asynchronously: a Keychain read during init can block the
        // main thread before the app has drawn anything.
        ClipboardStore.loadAsync { [weak self] restored in
            guard let self, self.clipboardItems.isEmpty else { return }
            self.clipboardItems = restored
        }
        // Trust the system over the settings file: the user may have switched
        // it off in System Settings since last launch.
        launchAtLogin = LoginItem.isEnabled
        shelfItems = ShelfStore.load()

        lastSavedSettings = snapshot()
        loaded = true

        // One debounced write covers every setting *and* the note text, instead
        // of a synchronous UserDefaults write on each keystroke.
        objectWillChange
            .debounce(for: .milliseconds(600), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                guard let self, self.loaded else { return }
                let settings = self.snapshot()
                self.publishWidgetSnapshot()
                guard settings != self.lastSavedSettings else { return }
                self.lastSavedSettings = settings
                SettingsStore.save(settings)
            }
            .store(in: &cancellables)

        // Re-publish subsystem changes so views observing `state` refresh.
        for publisher in [
            power.objectWillChange.eraseToAnyPublisher(),
            batteries.objectWillChange.eraseToAnyPublisher(),
            meetings.objectWillChange.eraseToAnyPublisher(),
            licensing.objectWillChange.eraseToAnyPublisher(),
            nowPlaying.objectWillChange.eraseToAnyPublisher(),
            audio.objectWillChange.eraseToAnyPublisher()
        ] {
            publisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }

        $clipboardItems
            .combineLatest($clipboardSearch)
            .map { items, query in
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return items.count }
                return items.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }.count
            }
            .removeDuplicates()
            .assign(to: &$visibleClipboardCount)

        refreshDiscordPresence()
        for name: NSNotification.Name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ] {
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDiscordPresence() }
            }
        }
    }

    // MARK: - Persistence

    private func apply(_ s: JendelaSettings) {
        quickNoteText = s.quickNoteText
        appliedTemplateID = s.appliedTemplateID
        selectedTemplateID = s.selectedTemplateID
        notchSize = NotchSize(rawValue: s.notchSize) ?? .standard
        expandOnHover = s.expandOnHover
        showTrackInCompact = s.showTrackInCompact
        showMusicIndicator = s.showMusicIndicator
        clipboardAutoCapture = s.clipboardAutoCapture
        clipboardLimit = s.clipboardLimit
        launchAtLogin = s.launchAtLogin
        hasOnboarded = s.hasOnboarded
        needsOnboarding = !s.hasOnboarded
        var keys: [HotKeyAction: HotKeyBinding] = [:]
        for action in HotKeyAction.allCases {
            keys[action] = s.hotKeys[action.rawValue] ?? action.defaultBinding
        }
        hotKeys = keys
        skipConcealedClipboard = s.skipConcealedClipboard
        clipboardExcludedApps = s.clipboardExcludedApps
        musicProvider = MusicProvider(rawValue: s.musicProvider) ?? .appleMusic
        discordPipEnabled = s.discordPipEnabled
        batterySaverMode = BatterySaverMode(rawValue: s.batterySaverMode) ?? .auto
        noteVisible = s.noteVisible
        selectedSection = NotchSection(rawValue: s.selectedSection) ?? .home
        studioSection = StudioSection(rawValue: s.studioSection) ?? .notch
        selectedCategory = s.selectedCategory
        syncWallpaperWithTheme = s.syncWallpaperWithTheme
        focusMinutes = s.focusMinutes
        showNotchHandle = s.showNotchHandle
        hideNotch = s.hideNotch
        ambientStyle = AmbientStyle(rawValue: s.ambientStyle) ?? .waveform
        musicIconStyle = MusicIconStyle(rawValue: s.musicIconStyle) ?? .automatic
        hubWidth = min(max(s.hubWidth, 340), 620)
        discordOverlayPinned = s.discordOverlayPinned
        discordOverlayOpacity = min(max(s.discordOverlayOpacity, 0.4), 1)
        discordChannelName = s.discordChannelName
        if s.discordOverlayFrame.count == 4 {
            discordOverlayFrame = NSRect(
                x: s.discordOverlayFrame[0], y: s.discordOverlayFrame[1],
                width: max(s.discordOverlayFrame[2], 210), height: max(s.discordOverlayFrame[3], 132)
            )
        }
        if !s.notes.isEmpty {
            notes = s.notes
        } else if s.noteFrame.count == 4 {
            // Carry the single note forward from before multiple notes existed.
            notes = [NoteRecord(id: UUID(), frame: s.noteFrame)]
        }
        let restored = s.enabledSections.compactMap(NotchSection.init(rawValue:))
        enabledSections = restored.isEmpty ? NotchSection.allCases : restored
        photoRotationMinutes = s.photoRotationMinutes
        photos = PhotoStore.existing(s.photos)
        originalWallpapers = s.originalWallpapers
    }

    private func snapshot() -> JendelaSettings {
        JendelaSettings(
            quickNoteText: quickNoteText,
            appliedTemplateID: appliedTemplateID,
            selectedTemplateID: selectedTemplateID,
            notchSize: notchSize.rawValue,
            expandOnHover: expandOnHover,
            showTrackInCompact: showTrackInCompact,
            showMusicIndicator: showMusicIndicator,
            clipboardAutoCapture: clipboardAutoCapture,
            skipConcealedClipboard: skipConcealedClipboard,
            clipboardLimit: clipboardLimit,
            clipboardExcludedApps: clipboardExcludedApps,
            launchAtLogin: launchAtLogin,
            hasOnboarded: hasOnboarded,
            hotKeys: Dictionary(uniqueKeysWithValues: hotKeys.map { ($0.key.rawValue, $0.value) }),
            musicProvider: musicProvider.rawValue,
            discordPipEnabled: discordPipEnabled,
            batterySaverMode: batterySaverMode.rawValue,
            noteVisible: noteVisible,
            selectedSection: selectedSection.rawValue,
            studioSection: studioSection.rawValue,
            selectedCategory: selectedCategory,
            syncWallpaperWithTheme: syncWallpaperWithTheme,
            focusMinutes: focusMinutes,
            showNotchHandle: showNotchHandle,
            hideNotch: hideNotch,
            ambientStyle: ambientStyle.rawValue,
            musicIconStyle: musicIconStyle.rawValue,
            hubWidth: hubWidth,
            notes: notes,
            discordOverlayFrame: [discordOverlayFrame.origin.x, discordOverlayFrame.origin.y,
                                  discordOverlayFrame.width, discordOverlayFrame.height],
            discordOverlayPinned: discordOverlayPinned,
            discordOverlayOpacity: discordOverlayOpacity,
            discordChannelName: discordChannelName,
            enabledSections: enabledSections.map(\.rawValue),
            photos: photos,
            photoRotationMinutes: photoRotationMinutes,
            originalWallpapers: originalWallpapers
        )
    }

    /// Shows the notes and brings one to the front. They normally live behind
    /// every app, so without the raise the click appears to do nothing.
    func showNotes() {
        noteVisible = true
        if notes.isEmpty { notes = [NoteRecord.next(after: [])] }
        closeNotch()
        let target = notes.first?.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.raiseNote?(target)
        }
    }

    func addNote() {
        let note = NoteRecord.next(after: notes)
        notes.append(note)
        noteVisible = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.raiseNote?(note.id)
        }
    }

    /// Removes a note and its text. The last one is emptied rather than closed,
    /// so there is always somewhere to write.
    func deleteNote(_ id: UUID) {
        NoteStore.remove(id)
        guard notes.count > 1 else {
            notes = [NoteRecord.next(after: [])]
            quickNoteText = ""
            publishWidgetSnapshot()
            return
        }
        notes.removeAll { $0.id == id }
        if let first = notes.first { quickNoteText = NoteStore.load(first.id).string }
        publishWidgetSnapshot()
    }

    func noteMoved(_ id: UUID, to frame: NSRect) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].frame = [frame.minX, frame.minY, frame.width, frame.height]
    }

    /// The widget shows the first note.
    func noteChanged(_ id: UUID, text: String) {
        guard notes.first?.id == id else { return }
        quickNoteText = text
    }

    // MARK: - Photos

    func addPhotos() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Add"
        panel.message = "Choose photos for the desktop widget"
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.compactMap { PhotoStore.addPhoto(from: $0) }
        guard !added.isEmpty else { return }
        photos.append(contentsOf: added)
        publishWidgetSnapshot()
    }

    func removePhoto(_ name: String) {
        photos.removeAll { $0 == name }
        PhotoStore.remove(name)
        publishWidgetSnapshot()
    }

    // MARK: - Widgets

    /// Hands the desktop widgets a fresh snapshot and reloads them — but only
    /// when the content actually differs, so an unrelated settings change does
    /// not wake the widget process for nothing.
    func publishWidgetSnapshot() {
        let payload = WidgetSnapshot(
            note: quickNoteText,
            clips: clipboardItems.prefix(8).map {
                WidgetSnapshot.Clip(
                    id: $0.id.uuidString,
                    title: $0.displayTitle,
                    kind: $0.kind.rawValue,
                    pinned: $0.pinned
                )
            },
            themeName: appliedTheme.name,
            startHex: appliedTheme.startHex,
            endHex: appliedTheme.endHex,
            accentHex: appliedTheme.accentHex,
            secondaryHex: appliedTheme.secondaryHex,
            photos: photos,
            photoRotationMinutes: photoRotationMinutes
        )
        guard payload != lastPublishedSnapshot else { return }
        lastPublishedSnapshot = payload
        guard SharedStore.save(payload) else { return }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    // MARK: - Derived

    /// The single answer to "should we be doing less". Decorative motion, live
    /// blur and fast polling all defer to this.
    var conserving: Bool {
        switch batterySaverMode {
        case .on: true
        case .off: false
        case .auto: power.shouldConserve
        }
    }

    var batterySaverActive: Bool { conserving }
    // The hub is deliberately opaque black so it merges with the notch, so
    // there is no blur left to reduce.
    var callIsActive: Bool { discordCameraOn || discordSharingOn }

    // MARK: - Licensing

    var isPro: Bool { licensing.isPro }
    var openStudio: (() -> Void)?

    /// Which tabs need a licence once the trial is over. The hub, notes, music
    /// and sound stay free forever — an app that stops being useful the moment
    /// a trial lapses does not earn goodwill.
    func requiresLicence(_ section: NotchSection) -> Bool {
        switch section {
        case .clipboard, .shelf, .day, .ai: return !isPro
        case .home, .music, .sound, .discord: return false
        }
    }

    /// Unlicensed history is short rather than absent, so the feature can still
    /// be understood before buying.
    var effectiveClipboardLimit: Int { isPro ? clipboardLimit : 5 }

    func paywallDetail(for section: NotchSection) -> String {
        switch section {
        case .clipboard: "Keep hundreds of copies, searchable and pinned, encrypted on this Mac."
        case .shelf: "Park files on the notch and drag them wherever they need to go."
        case .day: "Your next meeting with a join button, and every battery at a glance."
        case .ai: "Ask a question from the notch, using your own ChatGPT account."
        default: "Unlock the rest of Jendela."
        }
    }

    func openPurchasePage() {
        if let url = URL(string: "https://jendela.app/buy") { NSWorkspace.shared.open(url) }
    }

    func showLicenceEntry() {
        studioSection = .settings
        closeNotch()
        openStudio?()
    }

    /// What the hover gate consults. The AI tab used to set `notchPinned`
    /// outright, which left the hub pinned after you had merely visited it —
    /// so it never closed again. Focus is the honest signal.
    /// Holding the hub open for a focused chat field must expire, or walking
    /// away after typing leaves it open forever — focus alone is not evidence
    /// that anyone is still there.
    var holdsOpen: Bool {
        notchPinned || (chatFocused && Date().timeIntervalSince(lastChatKeystroke) < 4)
    }

    /// Size of the ambient indicator. The coordinator sized the panel from
    /// `showTrackInCompact` while the view drew itself from `ambientStyle`, so
    /// the two disagreed and the pill sat wrong beside the notch.
    var ambientSize: NSSize {
        switch ambientStyle {
        case .artwork: NSSize(width: 30, height: 30)
        case .title: NSSize(width: nowPlaying.track == nil ? 92 : 200, height: 30)
        case .waveform, .none: NSSize(width: 74, height: 30)
        }
    }

    /// Never empty, and never shows a section the user turned off.
    var visibleSections: [NotchSection] {
        enabledSections.isEmpty ? NotchSection.allCases : enabledSections
    }

    func setSection(_ section: NotchSection, enabled: Bool) {
        var next = visibleSections
        if enabled {
            guard !next.contains(section) else { return }
            // Keep the canonical order rather than the order they were re-added.
            next = NotchSection.allCases.filter { next.contains($0) || $0 == section }
        } else {
            guard next.count > 1 else { return }   // always leave one
            next.removeAll { $0 == section }
        }
        enabledSections = next
        if !next.contains(selectedSection) { selectedSection = next[0] }
    }

    var currentTrack: (title: String, artist: String) {
        if let track = nowPlaying.track {
            let artist = [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · ")
            return (track.title, artist.isEmpty ? track.source.rawValue : artist)
        }
        if nowPlaying.automationDenied {
            return ("Automation not allowed", "Grant access in Privacy & Security")
        }
        if musicProvider == .youtube {
            return ("Nothing playing", "Open music.youtube.com in your browser")
        }
        return ("Nothing playing", "Open \(musicProvider.rawValue) to start")
    }

    var isPlaying: Bool { nowPlaying.track?.isPlaying ?? false }

    var musicHintIsWarning: Bool {
        nowPlaying.automationDenied
            || (musicProvider == .youtube && (needsAccessibility || nowPlaying.youtubeScriptBlocked))
    }

    var musicHint: String {
        if musicProvider == .youtube {
            if nowPlaying.youtubeScriptBlocked && !needsAccessibility {
                return "For art and play state: View › Developer › Allow JavaScript from Apple Events"
            }
            return needsAccessibility
                ? "Allow Accessibility to control YouTube Music"
                : "Controlled with the media keys"
        }
        return nowPlaying.automationDenied
            ? "Allow Automation to control \(musicProvider.rawValue)"
            : "Choose where you listen"
    }

    /// Themes were removed as a browsable feature; a single accent remains so
    /// the hub, widgets and note keep one consistent colour.
    var selectedTheme: DesktopTheme { appliedTheme }
    var appliedTheme: DesktopTheme {
        DesktopTheme.templates.first(where: { $0.id == appliedTemplateID }) ?? DesktopTheme.templates[0]
    }

    var visibleClipboardItems: [ClipboardEntry] {
        let query = clipboardSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = query.isEmpty
            ? clipboardItems
            : clipboardItems.filter { $0.title.localizedCaseInsensitiveContains(query) }
        return matched.sorted { $0.pinned && !$1.pinned }
    }

    // MARK: - Theme

    func applyTheme(_ id: String) {
        appliedTemplateID = id
        guard syncWallpaperWithTheme else { return }
        refreshWallpaper()
    }

    func setHideNotch(_ enabled: Bool) {
        hideNotch = enabled
        refreshWallpaper()
    }

    func applyWallpaper() {
        syncWallpaperWithTheme = true
        refreshWallpaper()
    }

    /// Single place that decides what the desktop picture should be.
    ///
    /// - theme sync on  → render the gradient, masked if the notch is hidden
    /// - theme sync off, notch hidden → mask the user's own wallpaper
    /// - neither → put the user's original back
    func refreshWallpaper() {
        wallpaperError = nil

        if !syncWallpaperWithTheme && !hideNotch {
            restoreWallpapers()
            return
        }

        // Remember the real wallpaper before replacing it, and never mistake one
        // of our own generated files for the original.
        if originalWallpapers.isEmpty {
            let current = WallpaperRenderer.currentWallpapers()
            let originals = (0..<NSScreen.screens.count).map { index -> String in
                guard let url = current[index], !WallpaperRenderer.isGenerated(url) else { return "" }
                return url.path
            }
            if originals.contains(where: { !$0.isEmpty }) { originalWallpapers = originals }
        }

        let theme = appliedTheme
        let useTheme = syncWallpaperWithTheme
        let mask = hideNotch
        var jobs: [WallpaperRenderer.Job] = []

        for (index, screen) in NSScreen.screens.enumerated() {
            let scale = screen.backingScaleFactor
            let pixelSize = CGSize(
                width: screen.frame.width * scale,
                height: screen.frame.height * scale
            )
            let maskHeight = mask ? NotchMetrics.notch(on: screen).height * scale : 0

            let source: JendelaState.WallpaperSource?
            if useTheme {
                source = .theme
            } else if index < originalWallpapers.count, !originalWallpapers[index].isEmpty {
                source = .original(originalWallpapers[index])
            } else {
                source = nil
            }
            guard let source else { continue }

            let jobSource: WallpaperRenderer.Job.Source
            switch source {
            case .theme:
                jobSource = .gradient(
                    id: theme.id,
                    start: Self.rgb(theme.startHex),
                    end: Self.rgb(theme.endHex),
                    accent: Self.rgb(theme.accentHex)
                )
            case .original(let path):
                jobSource = .image(path: path)
            }
            jobs.append(.init(index: index, pixelSize: pixelSize, maskHeight: maskHeight, source: jobSource))
        }

        guard !jobs.isEmpty else {
            wallpaperError = "Could not read the current desktop picture"
            return
        }
        WallpaperRenderer.run(jobs) { [weak self] error in
            self?.wallpaperError = error == nil ? nil : "Could not set the desktop picture"
        }
    }

    enum WallpaperSource {
        case theme
        case original(String)
    }

    private static func rgb(_ hex: UInt32) -> WallpaperRenderer.RGB {
        let c = DesktopTheme.components(hex)
        return WallpaperRenderer.RGB(r: c.r, g: c.g, b: c.b)
    }

    private func restoreWallpapers() {
        guard !originalWallpapers.isEmpty else { return }
        var urls: [Int: URL] = [:]
        for (index, path) in originalWallpapers.enumerated() where !path.isEmpty {
            urls[index] = URL(fileURLWithPath: path)
        }
        WallpaperRenderer.set(urls)
        originalWallpapers = []
    }

    // MARK: - Focus timer

    func toggleFocus() {
        focusRunning ? stopFocus() : startFocus()
    }

    private func startFocus() {
        focusRemaining = max(1, focusMinutes) * 60
        focusRunning = true
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.focusRemaining -= 1
                if self.focusRemaining <= 0 { self.stopFocus() }
            }
        }
        // A countdown does not need second-accurate wakeups; the tolerance lets
        // macOS coalesce them with other timers instead of waking the CPU alone.
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        focusTimer = timer
    }

    private func stopFocus() {
        focusTimer?.invalidate()
        focusTimer = nil
        focusRunning = false
        focusRemaining = 0
    }

    var focusLabel: String {
        guard focusRunning else { return "Focus \(focusMinutes)m" }
        return String(format: "%d:%02d", focusRemaining / 60, focusRemaining % 60)
    }

    // MARK: - Discord

    func openDiscord() {
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.hnc.Discord"
        }) {
            app.activate()
            return
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.hnc.Discord") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Closing the overlay turns off whatever kept it on screen, so it does not
    /// immediately reappear.
    func hideDiscordOverlay() {
        discordOverlayPinned = false
        discordCameraOn = false
        discordSharingOn = false
    }

    private func refreshDiscordPresence() {
        discordRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.hnc.Discord"
        }
    }

    // MARK: - Clipboard

    /// Types password managers use to mark "do not record this".
    private static let concealedTypes: [NSPasteboard.PasteboardType] = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.AutoGeneratedType")
    ]
    static let imageByteCap = 8_000_000

    /// Set whenever *we* write to the pasteboard, so `ClipboardMonitor` can
    /// ignore the change it is about to observe instead of re-capturing it.
    private(set) var selfWrittenChangeCount: Int?

    func captureClipboard() {
        _ = captureClipboardIfChanged()
    }

    @discardableResult
    func captureClipboardIfChanged() -> Bool {
        let pasteboard = NSPasteboard.general

        if skipConcealedClipboard,
           let types = pasteboard.types,
           types.contains(where: { Self.concealedTypes.contains($0) }) {
            return false
        }

        // Whatever was frontmost is what produced the copy.
        if let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           clipboardExcludedApps.contains(source) {
            return false
        }

        let text = pasteboard.string(forType: .string)
        let fileURL = pasteboard.string(forType: .fileURL)
        // Resolve the bytes and the type in one read; the old code fetched the
        // image a second time purely to decide which type it was.
        let png = pasteboard.data(forType: .png)
        let imageData = png ?? pasteboard.data(forType: .tiff)
        let entry: ClipboardEntry?

        if let fileURL, !fileURL.isEmpty {
            let filename = URL(string: fileURL)?.lastPathComponent ?? fileURL
            entry = ClipboardEntry(
                kind: .file,
                title: filename.removingPercentEncoding ?? filename,
                subtitle: "Copied file",
                data: fileURL.data(using: .utf8),
                pasteboardType: .fileURL
            )
        } else if let imageData {
            // Truncating to the cap produced a corrupt image that we would then
            // paste back out; oversized images are noted but not stored.
            let tooBig = imageData.count > Self.imageByteCap
            let size = ByteCountFormatter.string(fromByteCount: Int64(imageData.count), countStyle: .file)
            entry = ClipboardEntry(
                kind: .image,
                title: tooBig ? "Image too large to keep" : "Screenshot / image",
                subtitle: tooBig ? "\(size) · over the 8 MB limit" : "Copied image · \(size)",
                data: tooBig ? nil : imageData,
                pasteboardType: tooBig ? nil : (png != nil ? .png : .tiff)
            )
        } else if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            entry = ClipboardEntry(
                kind: .text,
                title: text,
                subtitle: "Copied text",
                data: text.data(using: .utf8),
                pasteboardType: .string
            )
        } else {
            entry = nil
        }

        guard let entry else { return false }
        // Move an existing copy to the front rather than inserting a duplicate.
        if let index = clipboardItems.firstIndex(where: { $0.fingerprint == entry.fingerprint }) {
            guard index != 0 else { return false }
            let existing = clipboardItems.remove(at: index)
            clipboardItems.insert(existing, at: 0)
            return true
        }
        clipboardItems.insert(entry, at: 0)
        trimClipboard()
        return true
    }

    /// Pinned entries are never evicted.
    private func trimClipboard() {
        let cap = max(5, min(effectiveClipboardLimit, ClipboardStore.maxEntries))
        guard clipboardItems.filter({ !$0.pinned }).count > cap else { return }
        var kept: [ClipboardEntry] = []
        var unpinned = 0
        for item in clipboardItems {
            if item.pinned { kept.append(item); continue }
            if unpinned < cap { kept.append(item); unpinned += 1 }
        }
        clipboardItems = kept
    }

    func pasteClipboard(_ entry: ClipboardEntry) {
        guard let type = entry.pasteboardType, let data = entry.data else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: type)
        selfWrittenChangeCount = pasteboard.changeCount
        // Keep rows still under the pointer after copying.
    }

    /// Writes the entry as unformatted text, for pasting into somewhere that
    /// would otherwise inherit fonts and colours.
    func pastePlain(_ entry: ClipboardEntry) {
        let text: String
        switch entry.kind {
        case .text: text = entry.title
        case .file: text = entry.title
        case .image: return   // nothing sensible to paste as plain text
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        selfWrittenChangeCount = pasteboard.changeCount
    }

    func excludeFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let id = app.bundleIdentifier,
              id != Bundle.main.bundleIdentifier,
              !clipboardExcludedApps.contains(id)
        else { return }
        clipboardExcludedApps.append(id)
    }

    func removeClipboardExclusion(_ id: String) {
        clipboardExcludedApps.removeAll { $0 == id }
    }

    /// A readable name for an excluded bundle id, falling back to the id when
    /// the app is no longer installed.
    func displayName(forBundleID id: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path)
    }

    func togglePin(_ entry: ClipboardEntry) {
        guard let index = clipboardItems.firstIndex(where: { $0.id == entry.id }) else { return }
        clipboardItems[index].pinned.toggle()
        trimClipboard()
    }

    func removeClipboardItem(_ entry: ClipboardEntry) {
        clipboardItems.removeAll { $0.id == entry.id }
    }

    func clearClipboard() {
        clipboardItems.removeAll { !$0.pinned }
    }

    /// Removes the history and the file behind it.
    func wipeClipboardHistory() {
        clipboardItems = []
        ClipboardStore.wipe()
    }

    // MARK: - Music

    func openMusicProvider() {
        switch musicProvider {
        case .appleMusic:
            if let url = URL(string: "music://") { NSWorkspace.shared.open(url) }
        case .spotify:
            if let url = URL(string: "spotify:") { NSWorkspace.shared.open(url) }
        case .youtube:
            // Reuse the open tab rather than piling up new ones.
            guard !nowPlaying.focusYouTubeTab() else { return }
            if let url = URL(string: "https://music.youtube.com") { NSWorkspace.shared.open(url) }
        }
    }

    /// Transport state is no longer guessed locally — Music and Spotify
    /// broadcast the new state and `NowPlayingMonitor` picks it up.
    func performMusicCommand(_ command: String) {
        guard musicProvider == .youtube else {
            nowPlaying.command(command, provider: musicProvider)
            return
        }
        // Try the page itself first. Media keys are a fallback because macOS
        // routes them to whichever app owns "now playing" — with Music.app
        // running, a media key starts Music instead of the YouTube tab.
        // Nothing to control yet: open it, the way pressing play on an idle
        // player would.
        if nowPlaying.track == nil, !nowPlaying.focusYouTubeTab() {
            openMusicProvider()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.nowPlaying.refreshYouTube()
            }
            return
        }
        if nowPlaying.controlYouTube(command) {
            if command != "previous track" && command != "next track" {
                nowPlaying.youtubePlaying.toggle()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.nowPlaying.refreshYouTube()
            }
            return
        }
        guard MediaKey.isAllowed else { needsAccessibility = true; return }
        needsAccessibility = false
        switch command {
        case "previous track": MediaKey.previous.send()
        case "next track": MediaKey.next.send()
        default:
            MediaKey.playPause.send()
            nowPlaying.youtubePlaying.toggle()
        }
        // The tab title changes a moment after the key lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.nowPlaying.refreshYouTube()
        }
    }

    func requestAccessibility() {
        Permissions.request(.accessibility)
        needsAccessibility = !MediaKey.isAllowed
    }

    /// Opens the pane for whatever the hub is currently blocked on.
    func resolveMusicPermission() {
        if musicProvider == .youtube {
            Permissions.request(.accessibility)
            needsAccessibility = !MediaKey.isAllowed
        } else {
            Permissions.openSettings(.automation)
        }
    }

    /// The image to show beside the current track, honouring the chosen style.
    var musicIcon: NSImage? {
        _ = musicIconVersion   // re-evaluate after an import
        switch musicIconStyle {
        case .accent: return nil
        case .custom: return MusicIconStore.custom() ?? MusicIconStore.appIcon(for: musicProvider)
        case .appIcon: return MusicIconStore.appIcon(for: musicProvider)
        case .automatic: return nowPlaying.artwork ?? MusicIconStore.appIcon(for: musicProvider)
        }
    }

    func chooseMusicIcon() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Use"
        panel.message = "Choose an image for the music tile"
        guard panel.runModal() == .OK, let url = panel.urls.first else { return }
        guard MusicIconStore.importCustom(from: url) else { return }
        musicIconStyle = .custom
        musicIconVersion += 1
    }

    func clearMusicIcon() {
        MusicIconStore.removeCustom()
        if musicIconStyle == .custom { musicIconStyle = .automatic }
        musicIconVersion += 1
    }

    func refreshNowPlaying() {
        if musicProvider == .youtube {
            nowPlaying.refreshYouTube()
        } else {
            nowPlaying.refresh(provider: musicProvider)
        }
    }

    func previousTrack() { performMusicCommand("previous track") }
    func nextTrack() { performMusicCommand("next track") }
    func togglePlayPause() { performMusicCommand("playpause") }
}

@main
struct JendelaApp: App {
    static let studioWindowID = "studio"

    @NSApplicationDelegateAdaptor(JendelaAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Jendela Studio", id: JendelaApp.studioWindowID) {
            StudioView(state: delegate.state)
                .sheet(isPresented: Binding(
                    get: { delegate.state.needsOnboarding },
                    set: { delegate.state.needsOnboarding = $0 }
                )) {
                    OnboardingView(state: delegate.state)
                }
                .frame(minWidth: 1040, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 780)

        MenuBarExtra("Jendela", systemImage: "rectangle.topthird.inset.filled") {
            MenuBarView(state: delegate.state, delegate: delegate)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class JendelaAppDelegate: NSObject, NSApplicationDelegate {
    let state = JendelaState()
    private var notchCoordinator: NotchPanelCoordinator?
    private var musicIndicatorCoordinator: AmbientMusicIndicatorCoordinator?
    private var noteCoordinator: DesktopNoteCoordinator?
    private var discordCoordinator: DiscordOverlayCoordinator?
    private var clipboardMonitor: ClipboardMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar app: no Dock tile. The Studio window is reached from the
        // menu bar item instead.
        NSApp.setActivationPolicy(.accessory)
        notchCoordinator = NotchPanelCoordinator(state: state)
        musicIndicatorCoordinator = AmbientMusicIndicatorCoordinator(state: state)
        noteCoordinator = DesktopNoteCoordinator(state: state)
        discordCoordinator = DiscordOverlayCoordinator(state: state)
        clipboardMonitor = ClipboardMonitor(state: state)
        clipboardMonitor?.start()
        state.applyHotKeys()
        state.openStudio = { [weak state] in
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.identifier?.rawValue.contains(JendelaApp.studioWindowID) == true }?
                .makeKeyAndOrderFront(nil)
            _ = state
        }
        state.publishWidgetSnapshot()
        notchCoordinator?.show()
        musicIndicatorCoordinator?.show()
        // The note coordinator already follows `state.noteVisible`; showing it
        // here unconditionally overrode that and forced it on at every launch.
    }

    /// Reopening has to go through SwiftUI's `openWindow`: once the user closes
    /// the Studio window it is gone from `NSApp.windows`, so the old title
    /// lookup silently did nothing and there was no way back into the app.
    func showStudio(using openWindow: OpenWindowAction) {
        NSApp.activate(ignoringOtherApps: true)
        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue.contains(JendelaApp.studioWindowID) == true }) {
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: JendelaApp.studioWindowID)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.quickChat.shutdown()
    }

    func toggleNotch() {
        state.toggleHub()
    }

    func toggleNote() {
        // The coordinator follows `noteVisible` itself.
        state.noteVisible.toggle()
    }

    func showDiscordOverlay() {
        discordCoordinator?.show()
    }
}

@MainActor
final class ClipboardMonitor: NSObject {
    private let state: JendelaState
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var currentInterval: TimeInterval = 0

    /// macOS has no pasteboard-change notification, so this is the one place
    /// the app must poll. The cost is kept negligible three ways: the check is
    /// only a change-counter read, the interval stretches when the hub is shut
    /// or the machine is conserving, and a generous tolerance lets the system
    /// coalesce our wakeup with other timers instead of waking the CPU alone.
    private var desiredInterval: TimeInterval? {
        guard state.clipboardAutoCapture else { return nil }
        if state.notchExpanded { return 1 }
        return state.conserving ? 8 : 3
    }

    init(state: JendelaState) {
        self.state = state
        super.init()
    }

    func start() {
        state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reschedule() }
            .store(in: &cancellables)
        reschedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        currentInterval = 0
    }

    private func reschedule() {
        guard let interval = desiredInterval else { stop(); return }
        guard interval != currentInterval else { return }
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkClipboard() }
        }
        timer.tolerance = interval * 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        currentInterval = interval
    }

    private func checkClipboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount
        // Ignore the change we caused ourselves by pasting from the history.
        guard currentCount != state.selfWrittenChangeCount else { return }
        state.captureClipboardIfChanged()
    }
}

enum NotchMetrics {
    static let horizontalInset: CGFloat = 4
    /// Header row (44) + section picker (38) + divider (1) + content padding (24).
    static let chromeHeight: CGFloat = 107
    static let shadowInset: CGFloat = 6
    // Window geometry updates in one step: no spring, bounce or delayed hit area.
    /// How far the collapsed hub hangs *below* the menu bar.
    ///
    /// This is the whole trick: the menu-bar strip — and the notch cut-out
    /// itself — does not reliably deliver mouse events to an ordinary panel, so
    /// anything living entirely up there can be neither hovered nor clicked.
    /// The lip is the real hover target.
    static let hoverLip: CGFloat = 4

    /// The hub's open/close curve.
    ///
    /// The *panel* still snaps to its final size in one step — animating an
    /// NSWindow blocks the main thread and leaves it stranded at intermediate
    /// sizes. This drives the card drawn inside it instead, and the coordinator
    /// holds the window at full size until the card has finished, so nothing is
    /// ever clipped mid-flight.
    static let morph: Animation = .spring(duration: 0.38, bounce: 0.05)
    static let morphDuration: TimeInterval = 0.48

    struct Notch {
        var width: CGFloat
        var height: CGFloat
        var centreX: CGFloat
        var isReal: Bool
    }

    /// The actual notch, straight from AppKit, rather than a percentage of the
    /// screen width. `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` are the
    /// menu-bar strips either side of the camera housing; the gap between them
    /// is the notch.
    static func notch(on screen: NSScreen) -> Notch {
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            return Notch(
                width: right.minX - left.maxX,
                height: screen.frame.maxY - left.minY,
                centreX: (left.maxX + right.minX) / 2,
                isReal: true
            )
        }
        let bar = screen.safeAreaInsets.top > 0
            ? screen.safeAreaInsets.top
            : NSStatusBar.system.thickness
        return Notch(width: 180, height: bar, centreX: screen.frame.midX, isReal: false)
    }

    /// Height of the menu bar on the active screen; the expanded card insets its
    /// controls by this so none of them sit in the dead strip.
    static var menuBarInset: CGFloat {
        guard let screen = NSScreen.main else { return 32 }
        return notch(on: screen).height
    }

    /// Collapsed: exactly the notch's width, plus a lip below the menu bar.
    static func compactSize(on screen: NSScreen) -> NSSize {
        let notch = notch(on: screen)
        return NSSize(width: notch.width.rounded(), height: (notch.height + hoverLip).rounded())
    }

    static func cardHeight(
        for section: JendelaState.NotchSection,
        clipboardCount: Int,
        shelfCount: Int = 0
    ) -> CGFloat {
        menuBarInset + chromeHeight + section.contentHeight(clipboardCount: clipboardCount, shelfCount: shelfCount)
    }

    static func expandedSize(
        for section: JendelaState.NotchSection,
        clipboardCount: Int,
        size: JendelaState.NotchSize,
        width: CGFloat? = nil,
        shelfCount: Int = 0
    ) -> NSSize {
        NSSize(
            width: (width ?? size.expandedWidth).rounded(),
            height: cardHeight(for: section, clipboardCount: clipboardCount, shelfCount: shelfCount) + shadowInset
        )
    }

    /// Hangs `size` from the top of the screen, centred on the notch rather than
    /// on the screen, so it lines up on displays where they differ.
    static func topAlignedFrame(_ size: NSSize, on screen: NSScreen) -> NSRect {
        let notch = notch(on: screen)
        return NSRect(
            x: (notch.centreX - size.width / 2).rounded(),
            y: (screen.frame.maxY - size.height).rounded(),
            width: size.width,
            height: size.height
        )
    }
}

final class InteractiveNotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// AppKit otherwise constrains windows to `visibleFrame`, pushing the hub
    /// ~34pt below the top of the screen so its square top corners no longer
    /// tuck into the notch. These panels are deliberately menu-bar level.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
final class AmbientMusicIndicatorCoordinator {
    private let state: JendelaState
    private let panel: NSPanel
    private var cancellables = Set<AnyCancellable>()

    init(state: JendelaState) {
        self.state = state
        panel = InteractiveNotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = false
        panel.level = .statusBar  // after isFloatingPanel; see above
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
        panel.contentView = FirstClickHostingView(rootView: AmbientMusicIndicatorView(state: state))

        state.$notchExpanded
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        state.$showMusicIndicator
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        state.$notchSize
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        refresh()
    }

    func show() { refresh() }

    @objc private func screenConfigurationChanged() {
        refresh()
    }

    private func refresh() {
        guard state.showMusicIndicator, state.isPlaying, !state.notchExpanded else {
            panel.orderOut(nil)
            return
        }
        positionPanel()
        panel.orderFrontRegardless()
    }

    private func positionPanel() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let notch = NotchMetrics.notch(on: screen)
        let size = state.ambientSize
        if panel.frame.size != size { panel.setContentSize(size) }
        // Immediately right of the notch and vertically centred on it, so it
        // reads as sitting beside the notch rather than hanging below it.
        let origin = NSPoint(
            x: (notch.centreX + notch.width / 2 + 8).rounded(),
            y: (screen.frame.maxY - notch.height + (notch.height - size.height) / 2).rounded()
        )
        panel.setFrameOrigin(origin)
    }
}

@MainActor
final class DesktopNoteCoordinator {
    private let state: JendelaState
    private var panels: [UUID: NSPanel] = [:]
    private var cancellables = Set<AnyCancellable>()
    /// Kept per note so a deleted note's observers can be torn down with it.
    private var observers: [UUID: [Any]] = [:]

    /// Notes sit just above the desktop icons, behind every app.
    private static let restingLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
    )

    init(state: JendelaState) {
        self.state = state

        state.$notes
            .combineLatest(state.$noteVisible)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notes, visible in
                self?.sync(notes: notes, visible: visible)
            }
            .store(in: &cancellables)

        state.raiseNote = { [weak self] id in self?.raise(id) }
    }

    /// Creates windows for new notes, drops windows for deleted ones.
    private func sync(notes: [NoteRecord], visible: Bool) {
        let wanted = Set(notes.map(\.id))
        for (id, panel) in panels where !wanted.contains(id) {
            // Order matters: drop the observers first. Ordering the window out
            // makes it resign key, and the resign handler used to lower *and
            // re-show* it — which put a just-deleted note straight back on
            // screen as a duplicate.
            for token in observers[id] ?? [] { NotificationCenter.default.removeObserver(token) }
            observers.removeValue(forKey: id)
            panels.removeValue(forKey: id)
            panel.orderOut(nil)
        }
        for note in notes {
            let panel = panels[note.id] ?? make(note)
            panels[note.id] = panel
            visible ? panel.orderFrontRegardless() : panel.orderOut(nil)
        }
    }

    private func make(_ note: NoteRecord) -> NSPanel {
        let panel = InteractiveNotchPanel(
            contentRect: note.rect,
            // `.resizable` on a borderless window still gives live edge drags,
            // so a note can be any size without growing a title bar.
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = Self.restingLevel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 180, height: 120)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = FirstClickHostingView(
            rootView: DesktopNoteView(state: state, note: note)
        )
        panel.setFrame(note.rect, display: false)

        var tokens: [Any] = []
        tokens.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.lower(note.id) }
        })
        for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            tokens.append(NotificationCenter.default.addObserver(
                forName: name, object: panel, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let live = self.panels[note.id] else { return }
                    self.state.noteMoved(note.id, to: live.frame)
                }
            })
        }
        observers[note.id] = tokens
        return panel
    }

    /// Brings one note above normal windows and gives it keyboard focus.
    private func raise(_ id: UUID?) {
        let panel = id.flatMap { panels[$0] } ?? panels.values.first
        guard let panel else { return }
        _ = id
        panel.level = .floating
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Only ever acts on a note we still own, so a deleted one cannot be
    /// resurrected by a late notification.
    private func lower(_ id: UUID) {
        guard let panel = panels[id] else { return }
        panel.level = Self.restingLevel
        guard state.noteVisible else { return }
        panel.orderFrontRegardless()
    }
}


struct StudioView: View {
    @ObservedObject var state: JendelaState

    var body: some View {
        HStack(spacing: 0) {
            StudioSidebar(state: state)
                .frame(width: 218)
            Divider().overlay(.white.opacity(0.08))
            Group {
                switch state.studioSection {
                case .notch:
                    NotchStudioView(state: state)
                case .widgets:
                    WidgetLibraryView(state: state)
                case .photos:
                    PhotoLibraryView(state: state)
                case .settings:
                    SettingsStudioView(state: state)
                case .instructions:
                    InstructionsStudioView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(hex: 0x101116))
        .foregroundStyle(.white)
        .tint(state.appliedTheme.accentColor)
    }
}

struct StudioSidebar: View {
    @ObservedObject var state: JendelaState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [state.appliedTheme.accentColor, state.appliedTheme.secondaryColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: 36)
                    .overlay { Image(systemName: "sparkles").font(.system(size: 14, weight: .bold)) }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Jendela.").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Desktop studio").font(.caption2).foregroundStyle(.white.opacity(0.42))
                }
            }
            .padding(.top, 46)
            .padding(.horizontal, 20)
            .padding(.bottom, 26)

            Text("CREATE")
                .font(.system(size: 9, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.3))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            ForEach(JendelaState.StudioSection.allCases) { section in
                Button {
                    state.studioSection = section
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 20)
                        Text(section.rawValue)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(state.studioSection == section ? .white : .white.opacity(0.56))
                    .padding(.horizontal, 13)
                    .frame(height: 38)
                    .background(
                        state.studioSection == section ? state.appliedTheme.accentColor.opacity(0.18) : .clear,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Circle().fill(Color.green).frame(width: 7, height: 7)
                    Text("Running quietly").font(.caption.weight(.semibold))
                }
                Text("Native · Local · Battery aware")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .padding(14)
        }
        .background(Color(hex: 0x0B0C10))
    }
}

struct StudioTopBar: View {
    let title: String
    let subtitle: String
    @ObservedObject var state: JendelaState
    var showsSearch = false

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.42))
            }
            Spacer()
            if showsSearch {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.36))
                    TextField("Search themes", text: $state.templateSearch)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(width: 190, height: 34)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(spacing: 7) {
                Circle().fill(state.batterySaverActive ? Color.green : Color.orange).frame(width: 7, height: 7)
                Text(state.batterySaverActive ? "Low energy" : "Full effects").font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(.white.opacity(0.055), in: Capsule())
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(Color(hex: 0x101116))
        .overlay(alignment: .bottom) { Divider().opacity(0.12) }
    }
}

struct ThemeHeroView: View {
    @ObservedObject var state: JendelaState
    let theme: DesktopTheme

    var body: some View {
        HStack(spacing: 0) {
            ThemeDesktopScene(theme: theme, compact: false)
                .frame(maxWidth: .infinity)
                .frame(height: 265)
            VStack(alignment: .leading, spacing: 16) {
                Text("SELECTED LOOK")
                    .font(.system(size: 9, weight: .bold)).tracking(1.2)
                    .foregroundStyle(.white.opacity(0.38))
                VStack(alignment: .leading, spacing: 5) {
                    Text(theme.name).font(.system(size: 22, weight: .bold, design: .rounded))
                    Text(theme.subtitle).font(.caption).foregroundStyle(.white.opacity(0.48))
                }
                HStack(spacing: 7) {
                    ForEach([theme.startColor, theme.endColor, theme.accentColor, theme.secondaryColor], id: \.self) { color in
                        Circle().fill(color).frame(width: 22, height: 22)
                            .overlay { Circle().stroke(.white.opacity(0.18), lineWidth: 1) }
                    }
                }
                Spacer()
                Button {
                    state.applyTheme(theme.id)
                } label: {
                    HStack {
                        Image(systemName: state.appliedTemplateID == theme.id ? "checkmark" : "sparkles")
                        Text(state.appliedTemplateID == theme.id ? "Applied to desktop" : "Apply this theme")
                    }
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(theme.accentColor, in: RoundedRectangle(cornerRadius: 11))
                    .foregroundStyle(Color.black.opacity(0.78))
                }
                .buttonStyle(.plain)

                Button {
                    state.applyTheme(theme.id)
                    state.applyWallpaper()
                } label: {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                        Text("Set as desktop picture")
                    }
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)

                if let error = state.wallpaperError {
                    Text(error).font(.caption2).foregroundStyle(.orange)
                }
            }
            .padding(22)
            .frame(width: 240)
            .background(.black.opacity(0.3))
        }
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.09), lineWidth: 1) }
    }
}

struct ThemeTemplateCard: View {
    @ObservedObject var state: JendelaState
    let theme: DesktopTheme

    var body: some View {
        Button {
            state.selectedTemplateID = theme.id
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                ThemeDesktopScene(theme: theme, compact: true)
                    .frame(height: 142)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(theme.name).font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text(theme.subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    if state.appliedTemplateID == theme.id {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accentColor)
                    } else if state.selectedTemplateID == theme.id {
                        Circle().fill(theme.accentColor).frame(width: 7, height: 7)
                    }
                }
            }
            .padding(10)
            .background(.white.opacity(state.selectedTemplateID == theme.id ? 0.085 : 0.04), in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(state.selectedTemplateID == theme.id ? theme.accentColor.opacity(0.72) : .white.opacity(0.07), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ThemeDesktopScene: View {
    let theme: DesktopTheme
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [theme.startColor, theme.endColor], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(theme.accentColor.opacity(0.24))
                    .frame(width: proxy.size.width * 0.62)
                    .blur(radius: compact ? 22 : 40)
                    .offset(x: proxy.size.width * 0.24, y: proxy.size.height * 0.18)
                VStack(spacing: 0) {
                    HStack {
                        Text("● Jendela")
                        Spacer()
                        Text("9:41")
                    }
                    .font(.system(size: compact ? 6 : 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, compact ? 7 : 11)
                    .frame(height: compact ? 14 : 20)
                    .background(.black.opacity(0.5))
                    Spacer()
                }
                HStack(alignment: .bottom, spacing: compact ? 5 : 9) {
                    VStack(alignment: .leading, spacing: compact ? 1 : 3) {
                        Text("09:41").font(.system(size: compact ? 17 : 30, weight: .bold, design: .rounded))
                        Text("WED · SEPT 09").font(.system(size: compact ? 4 : 7, weight: .bold)).tracking(0.8)
                    }
                    .padding(compact ? 7 : 12)
                    .frame(width: proxy.size.width * 0.42, alignment: .leading)
                    .background(.black.opacity(0.54), in: RoundedRectangle(cornerRadius: compact ? 7 : 12))
                    VStack(alignment: .leading, spacing: compact ? 3 : 5) {
                        HStack { Circle().fill(theme.accentColor).frame(width: compact ? 4 : 7); Text("TODAY") }
                        Text("Design your calm space").lineLimit(1)
                        Text("Keep only what matters").lineLimit(1)
                    }
                    .font(.system(size: compact ? 5 : 8, weight: .medium))
                    .padding(compact ? 7 : 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: compact ? 7 : 12))
                }
                .foregroundStyle(.white)
                .padding(compact ? 8 : 14)
                .padding(.top, compact ? 13 : 20)
            }
        }
    }
}

struct PhotoLibraryView: View {
    @ObservedObject var state: JendelaState

    private let rotations = [5, 15, 30, 60, 180]

    var body: some View {
        VStack(spacing: 0) {
            StudioTopBar(
                title: "Photos",
                subtitle: "Pictures for the desktop Photo widget.",
                state: state
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Button {
                            state.addPhotos()
                        } label: {
                            Label("Add Photos…", systemImage: "plus")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(state.appliedTheme.accentColor, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(Color.black.opacity(0.78))
                        }
                        .buttonStyle(.plain)

                        if state.photos.count > 1 {
                            HStack(spacing: 8) {
                                Text("Change every")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                                Picker("", selection: $state.photoRotationMinutes) {
                                    ForEach(rotations, id: \.self) { minutes in
                                        Text(minutes < 60 ? "\(minutes) min" : "\(minutes / 60) hr").tag(minutes)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 110)
                            }
                        }
                        Spacer()
                        Text("\(state.photos.count) photo\(state.photos.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    if state.photos.isEmpty {
                        VStack(spacing: 9) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 26, weight: .light))
                                .foregroundStyle(.white.opacity(0.3))
                            Text("No photos yet")
                                .font(.subheadline.weight(.semibold))
                            Text("Add a few, then place the Photo widget on your desktop.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.42))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 54)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 17))
                        .overlay { RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.07)).allowsHitTesting(false) }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                            ForEach(state.photos, id: \.self) { name in
                                PhotoTile(name: name) { state.removePhoto(name) }
                            }
                        }
                    }

                    Text("Photos are copied into Jendela and downscaled once, so the widget never resizes them while it draws. Rotation is built into the widget timeline — macOS switches pictures itself without waking the app.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.36))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(26)
            }
        }
    }
}

struct PhotoTile: View {
    let name: String
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = PhotoStore.image(named: name) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.06)
                }
            }
            .frame(height: 104)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            if hovering {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(.black.opacity(0.7), in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(7)
                .help("Remove photo")
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.white.opacity(hovering ? 0.25 : 0.08))
        }
        .onHover { hovering = $0 }
    }
}

struct WidgetLibraryView: View {
    @ObservedObject var state: JendelaState

    var body: some View {
        VStack(spacing: 0) {
            StudioTopBar(title: "Widget library", subtitle: "Choose what earns a place on your desktop.", state: state)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 235), spacing: 16)], spacing: 16) {
                    WidgetLibraryCard(title: "Quick Notes", detail: "Editable notes on the desktop, behind your apps", symbol: "note.text", color: .yellow, enabled: $state.noteVisible)
                    WidgetLibraryCard(title: "Clipboard", detail: "Automatically captures text, files, and screenshots", symbol: "doc.on.clipboard", color: .blue, enabled: $state.clipboardAutoCapture)
                    WidgetLibraryCard(title: "Now Playing", detail: "Music controls and artwork", symbol: "music.note", color: .pink, enabled: .constant(true))
                    WidgetLibraryCard(title: "Discord Mini View", detail: "Call picture-in-picture", symbol: "video.fill", color: .indigo, enabled: $state.discordPipEnabled)
                    WidgetLibraryCard(title: "Sound", detail: "Volume and output devices", symbol: "speaker.wave.2.fill", color: .cyan, enabled: .constant(true))
                    WidgetLibraryCard(
                        title: "Focus Timer",
                        detail: state.focusRunning ? "Running · \(state.focusLabel)" : "Quiet \(state.focusMinutes)-minute sessions",
                        symbol: "timer",
                        color: .orange,
                        enabled: Binding(get: { state.focusRunning }, set: { _ in state.toggleFocus() })
                    )
                }
                .padding(26)
            }
        }
    }
}

struct WidgetLibraryCard: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    @Binding var enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(color)
                Spacer()
                Toggle("", isOn: $enabled).labelsHidden().toggleStyle(.switch)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.42))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 17))
        .overlay { RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.075)) }
    }
}

struct InstructionsStudioView: View {
    @ObservedObject var state: JendelaState

    var body: some View {
        VStack(spacing: 0) {
            StudioTopBar(title: "Instructions", subtitle: "A few calm defaults to make Jendela feel right.", state: state)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    InstructionCard(number: "01", title: "Pick a look", detail: "Choose a theme, then press Apply this theme. The color system follows the look across the studio, notch, and desktop note.")
                    InstructionCard(number: "02", title: "Keep the desktop quiet", detail: "Quick Notes live at desktop level, behind normal apps. Hide them from the Widgets section whenever you need a clean canvas.")
                    InstructionCard(number: "03", title: "Let the hub do the busy work", detail: "Clipboard, music, sound, and Discord controls stay inside the compact notch hub until you ask for them.")
                    InstructionCard(number: "04", title: "Save battery", detail: "Battery Saver pauses decorative motion and avoids continuous refresh. Jendela remains event-driven while idle.")
                }
                .padding(26)
            }
        }
    }
}

struct InstructionCard: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.38))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.48)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 15))
        .overlay { RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.07)).allowsHitTesting(false) }
    }
}

struct SectionToggle: View {
    @ObservedObject var state: JendelaState
    let section: JendelaState.NotchSection

    private var enabled: Bool { state.visibleSections.contains(section) }
    /// The last remaining tab cannot be switched off, so it is shown as locked
    /// rather than silently ignoring the click.
    private var locked: Bool { enabled && state.visibleSections.count == 1 }

    var body: some View {
        Button {
            state.setSection(section, enabled: !enabled)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                Text(section.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: locked ? "lock.fill" : (enabled ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 11))
                    .foregroundStyle(enabled ? state.appliedTheme.accentColor : .white.opacity(0.25))
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(
                enabled ? .white.opacity(0.09) : .white.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .foregroundStyle(enabled ? .white : .white.opacity(0.45))
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .help(locked ? "The hub needs at least one tab" : (enabled ? "Hide from the hub" : "Show in the hub"))
    }
}

struct NotchStudioView: View {
    @ObservedObject var state: JendelaState

    var body: some View {
        VStack(spacing: 0) {
            StudioTopBar(title: "Notch Hub", subtitle: "A compact doorway to the things you use most.", state: state)
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 18) {
                        NotchPreview(state: state)
                            .scaleEffect(1.35)
                        Text("Hover briefly to open · click a tab to switch · pin to keep open · Esc to close")
                            .font(.caption).foregroundStyle(.white.opacity(0.42))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
                    .background(Color(hex: 0x17181D), in: RoundedRectangle(cornerRadius: 20))

                    ControlCard(
                        title: "What the hub shows",
                        subtitle: "Pick the tabs you actually use",
                        symbol: "square.grid.2x2"
                    ) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(JendelaState.NotchSection.allCases) { section in
                                SectionToggle(state: state, section: section)
                            }
                        }
                        Text("The hub keeps at least one tab, and resizes to whichever one is open.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }

                    HStack(alignment: .top, spacing: 16) {
                        ControlCard(title: "Notch behavior", subtitle: "Compact until you need it", symbol: "rectangle.topthird.inset.filled") {
                            Picker("Size", selection: $state.notchSize) {
                                ForEach(JendelaState.NotchSize.allCases) { size in
                                    Text(size.rawValue).tag(size)
                                }
                            }
                            .pickerStyle(.segmented)
                            Toggle("Expand on hover", isOn: $state.expandOnHover)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Hub width")
                                    Spacer()
                                    Text("\(Int(state.hubWidth)) pt")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                                Slider(value: $state.hubWidth, in: 340...620, step: 2)
                            }
                            Button(state.notchExpanded ? "Collapse hub" : "Expand hub") { state.toggleHub() }
                                .buttonStyle(SoftButtonStyle())
                        }
                        ControlCard(title: "Power profile", subtitle: "No continuous refresh", symbol: "leaf.fill") {
                            Picker("Battery saver", selection: $state.batterySaverMode) {
                                ForEach(JendelaState.BatterySaverMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text(state.batterySaverActive
                                 ? "Conserving — \(state.power.reason). Motion and blur are off."
                                 : "Full effects. Automatic mode follows Low Power Mode, battery and heat.")
                                .font(.caption2).foregroundStyle(.white.opacity(0.45))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ControlCard(
                        title: "While music plays",
                        subtitle: "Shown beside the notch when the hub is closed",
                        symbol: "waveform"
                    ) {
                        Toggle("Show something beside the notch", isOn: $state.showMusicIndicator)
                        if state.showMusicIndicator {
                            Picker("", selection: $state.ambientStyle) {
                                ForEach(JendelaState.AmbientStyle.allCases) { style in
                                    Text(style.label).tag(style)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            Text(state.ambientStyle.detail)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.45))
                            Text("The bars only move while something is playing and the Mac is not conserving power. Lyrics are not offered: no player exposes them without a separate lyrics service.")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.32))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ControlCard(
                        title: "Music tile",
                        subtitle: "What shows next to the track",
                        symbol: "photo.on.rectangle.angled"
                    ) {
                        HStack(alignment: .top, spacing: 14) {
                            TrackArtwork(state: state, size: 58, corner: 13, symbolSize: 20)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(.white.opacity(0.1))
                                }
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("", selection: $state.musicIconStyle) {
                                    ForEach(MusicIconStyle.allCases) { style in
                                        Text(style.label).tag(style)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)

                                Text(state.musicIconStyle.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.45))
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 8) {
                                    Button("Choose image…") { state.chooseMusicIcon() }
                                        .buttonStyle(SoftButtonStyle())
                                    if MusicIconStore.custom() != nil {
                                        Button("Remove") { state.clearMusicIcon() }
                                            .buttonStyle(SoftButtonStyle())
                                    }
                                }
                            }
                        }
                        Text("App icons are read from the installed player, so they are always the real, current icon.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.32))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ControlCard(title: "Music connections", subtitle: "Apple Music, Spotify, or YouTube Music", symbol: "music.note") {
                        Picker("Provider", selection: $state.musicProvider) {
                            ForEach(MusicProvider.allCases) { provider in
                                Label(provider.rawValue, systemImage: provider.symbol).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)
                        Button("Open \(state.musicProvider.rawValue)") { state.openMusicProvider() }
                            .buttonStyle(SoftButtonStyle())
                    }
                }
                .padding(26)
            }
        }
    }
}

struct SettingsStudioView: View {
    @ObservedObject var state: JendelaState

    var body: some View {
        VStack(spacing: 0) {
            StudioTopBar(title: "Settings", subtitle: "Privacy-first controls for a quiet background app.", state: state)
            VStack(spacing: 14) {
                SettingsRow(
                    title: "Hide the notch",
                    detail: "Blacks out the menu bar in your desktop picture so the notch disappears",
                    symbol: "rectangle.topthird.inset.filled"
                ) {
                    Toggle("", isOn: Binding(
                        get: { state.hideNotch },
                        set: { state.setHideNotch($0) }
                    )).labelsHidden()
                }
                SettingsRow(title: "Show Quick Notes", detail: "Notes stay at desktop level, behind normal apps", symbol: "note.text") {
                    Toggle("", isOn: $state.noteVisible).labelsHidden()
                }
                SettingsRow(title: "Automatic clipboard", detail: "Capture new text, files, and copied screenshots", symbol: "doc.on.clipboard") {
                    Toggle("", isOn: $state.clipboardAutoCapture).labelsHidden()
                }
                SettingsRow(title: "Discord picture-in-picture", detail: "Show a mini call panel after switching apps", symbol: "pip.fill") {
                    Toggle("", isOn: $state.discordPipEnabled).labelsHidden()
                }
                SettingsRow(
                    title: "Battery saver",
                    detail: state.batterySaverActive
                        ? "Conserving — \(state.power.reason)"
                        : "Automatic follows Low Power Mode, battery and heat",
                    symbol: "leaf.fill"
                ) {
                    Picker("", selection: $state.batterySaverMode) {
                        ForEach(JendelaState.BatterySaverMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                LicenceCard(state: state)

                ControlCard(
                    title: "Keyboard shortcuts",
                    subtitle: "Reach the hub without the pointer",
                    symbol: "command"
                ) {
                    ForEach(HotKeyAction.allCases) { action in
                        HStack {
                            Text(action.title).font(.system(size: 12))
                            Spacer()
                            HotKeyRecorder(action: action, state: state)
                        }
                    }
                    Text("Click a shortcut, then press the keys. Esc cancels. A modifier is required so an ordinary keystroke is never captured.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.38))
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsRow(
                    title: "Open at login",
                    detail: LoginItem.deniedByUser
                        ? "Turned off in System Settings › Login Items"
                        : "Start Jendela. automatically",
                    symbol: "power"
                ) {
                    Toggle("", isOn: $state.launchAtLogin).labelsHidden()
                }
                SettingsRow(
                    title: "Clipboard history",
                    detail: "Kept encrypted on this Mac · \(state.clipboardItems.count) stored",
                    symbol: "clock.arrow.circlepath"
                ) {
                    HStack(spacing: 8) {
                        Picker("", selection: $state.clipboardLimit) {
                            ForEach([25, 50, 100, 200], id: \.self) { Text("\($0)").tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 76)
                        Button("Erase") { state.wipeClipboardHistory() }
                    }
                }
                SettingsRow(title: "Show notch handle", detail: "Draw a small tab under the notch instead of staying invisible", symbol: "rectangle.topthird.inset.filled") {
                    Toggle("", isOn: $state.showNotchHandle).labelsHidden()
                }
                SettingsRow(
                    title: "Never record from…",
                    detail: state.clipboardExcludedApps.isEmpty
                        ? "Add an app whose copies should be ignored"
                        : state.clipboardExcludedApps.map { state.displayName(forBundleID: $0) }
                            .joined(separator: ", "),
                    symbol: "eye.slash"
                ) {
                    Menu {
                        Button("Add the frontmost app") { state.excludeFrontmostApp() }
                        if !state.clipboardExcludedApps.isEmpty {
                            Divider()
                            ForEach(state.clipboardExcludedApps, id: \.self) { id in
                                Button("Remove \(state.displayName(forBundleID: id))") {
                                    state.removeClipboardExclusion(id)
                                }
                            }
                        }
                    } label: {
                        Text("Manage")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                SettingsRow(title: "Skip password copies", detail: "Ignore items marked concealed by password managers", symbol: "lock.fill") {
                    Toggle("", isOn: $state.skipConcealedClipboard).labelsHidden()
                }
                SettingsRow(title: "Theme sets desktop picture", detail: "Applying a theme renders and sets a matching wallpaper", symbol: "photo.fill") {
                    Toggle("", isOn: Binding(
                        get: { state.syncWallpaperWithTheme },
                        set: { state.syncWallpaperWithTheme = $0; state.refreshWallpaper() }
                    )).labelsHidden()
                }
                Spacer()
            }
            .padding(26)
        }
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    let detail: String
    let symbol: String
    @ViewBuilder let accessory: Accessory

    init(title: String, detail: String, symbol: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).frame(width: 34, height: 34).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.42))
            }
            Spacer()
            accessory
        }
        .padding(16)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 15))
        .overlay { RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.07)).allowsHitTesting(false) }
    }
}

struct CategoryButtonStyle: ButtonStyle {
    let selected: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .foregroundStyle(selected ? Color.black.opacity(0.78) : .white.opacity(0.58))
            .background(selected ? accent : .white.opacity(configuration.isPressed ? 0.09 : 0.05), in: Capsule())
    }
}

/// The hub's outline. `radius` is animatable, so the corners round out as the
/// card grows instead of snapping at the end of the transition.
struct NotchCardShape: Shape {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: radius,
            bottomTrailingRadius: radius,
            topTrailingRadius: 0,
            style: .continuous
        )
        .path(in: rect)
    }
}

struct NotchPanelView: View {
    @ObservedObject var state: JendelaState
    private var isHovering: Bool { state.notchHovered }

    private var expanded: Bool { state.notchExpanded }

    /// Width the content is *always* laid out at. Keeping it fixed means text
    /// never reflows mid-animation — the shape clips it instead, which is what
    /// makes the growth read as one object rather than a re-layout.
    private var contentWidth: CGFloat {
        state.hubWidth - NotchMetrics.horizontalInset * 2
    }

    private var expandedHeight: CGFloat {
        NotchMetrics.cardHeight(
            for: state.selectedSection,
            clipboardCount: state.visibleClipboardCount,
            shelfCount: state.shelfItems.count
        )
    }

    private var cardWidth: CGFloat {
        guard let screen = NSScreen.main else { return contentWidth }
        return expanded ? contentWidth : NotchMetrics.notch(on: screen).width
    }

    private var cardHeight: CGFloat {
        guard let screen = NSScreen.main else { return expandedHeight }
        return expanded ? expandedHeight : NotchMetrics.compactSize(on: screen).height
    }

    private var cardRadius: CGFloat { expanded ? 24 : 11 }

    /// Everything the morph interpolates, as one value.
    private struct CardGeometry: Equatable {
        var width: CGFloat
        var height: CGFloat
        var radius: CGFloat
        var expanded: Bool
    }

    private var geometry: CardGeometry {
        CardGeometry(width: cardWidth, height: cardHeight, radius: cardRadius, expanded: expanded)
    }

    /// Invisible while idle, so nothing is drawn on the desktop.
    private var collapsedFill: Double {
        if expanded { return 0 }
        return state.showNotchHandle ? 1 : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if expanded {
                    cardContent
                        .frame(width: contentWidth, height: expandedHeight, alignment: .top)
                        // Fades in just behind the growing card, and leaves
                        // quickly so the shape is not chasing stale content.
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.09)),
                            removal: .opacity.animation(.easeIn(duration: 0.11))
                        ))
                } else {
                    Capsule()
                        .fill(.white.opacity(state.showNotchHandle ? 0.34 : 0))
                        .frame(width: 26, height: 2.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 4)
                }
            }
            .frame(width: cardWidth, height: cardHeight, alignment: .top)
            // One opaque black surface, the same black as the notch cut-out.
            // No material, no border: a tinted fill or a stroked edge is exactly
            // what makes it read as a separate window hanging below the notch
            // rather than the notch itself growing.
            .background {
                NotchCardShape(radius: cardRadius)
                    .fill(.black)
                    .opacity(expanded ? 1 : collapsedFill)
            }
            .clipShape(NotchCardShape(radius: cardRadius))
            // Shadow is cast downward only, and never near the top edge, so the
            // join with the physical notch stays invisible.
            .shadow(color: .black.opacity(expanded ? 0.45 : 0), radius: 14, y: 8)
            // Driven by value rather than `withAnimation` at the mutation site:
            // the coordinator flips `notchExpanded` from several places
            // (hover, click, Esc, menu bar) and every one of them should animate.
            // A single animation over one composite value. Three separate
            // `.animation` modifiers on overlapping properties meant a tab
            // switch started two competing animations of the same frame, which
            // is what still read as a jump.
            .animation(NotchMetrics.morph, value: geometry)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onHover { state.pointerAtNotch?($0) }
        .onExitCommand { state.closeNotch() }
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            notchTop
            sectionPicker
            Divider().overlay(.white.opacity(0.08))
            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 14)
                .padding(.top, 11)
                .padding(.bottom, 13)
        }
        .padding(.top, NotchMetrics.menuBarInset)
    }

    private var notchTop: some View {
        HStack {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [state.appliedTheme.accentColor, state.appliedTheme.secondaryColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                    .layoutPriority(1)
                    .overlay { Image(systemName: "sparkles").font(.caption.weight(.bold)) }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Jendela.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text("Desktop is calm")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                }
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(Color.green).frame(width: 6, height: 6)
                Text(state.batterySaverActive ? state.power.reason : "Full effects")
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(.white.opacity(0.68))
            Button {
                state.notchPinned.toggle()
            } label: {
                Image(systemName: state.notchPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(state.notchPinned ? state.appliedTheme.accentColor.opacity(0.22) : .white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.notchPinned ? "Unpin hub" : "Pin hub")
            .help(state.notchPinned ? "Unpin: close when the pointer leaves" : "Keep open while working elsewhere")
            Button {
                state.closeNotch()
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Close hub")
                    .background(.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 7)
    }

    private var sectionPicker: some View {
        HStack(spacing: 5) {
            ForEach(state.visibleSections) { section in
                Button {
                    state.selectedSection = section
                    if section == .music { state.refreshNowPlaying() }
                    if section == .day {
                        state.batteries.refresh()
                        state.meetings.refresh()
                    }
                    // The chat tab no longer pins. `chatFocused` holds the hub
                    // open only while the field actually has focus, so moving
                    // the pointer away still closes it.
                    if section != .ai { state.chatFocused = false }
                } label: {
                    Label(section.rawValue, systemImage: section.symbol)
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                        .background(
                            state.selectedSection == section ? .white.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(state.selectedSection == section ? .white : .white.opacity(0.38))
                .help(section.rawValue)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var sectionContent: some View {
        Group {
            if state.requiresLicence(state.selectedSection) {
                PaywallView(
                    state: state,
                    feature: state.selectedSection.rawValue,
                    detail: state.paywallDetail(for: state.selectedSection)
                )
            } else {
                switch state.selectedSection {
            case .home: HomeNotchSection(state: state)
            case .clipboard: ClipboardNotchSection(state: state)
            case .music: MusicNotchSection(state: state)
            case .sound: SoundNotchSection(state: state)
            case .discord: DiscordNotchSection(state: state)
            case .shelf:
                ShelfNotchSection(state: state)
            case .day:
                DayNotchSection(state: state)
                case .ai:
                QuickChatView(client: state.quickChat) { [weak state] focused in
                    state?.chatFocused = focused
                    if focused { state?.noteChatActivity() }
                } onActivity: { [weak state] in
                    state?.noteChatActivity()
                }
                }
            }
        }
        // A bare `switch` gives each branch its own identity with no transition
        // between them, so tabs hard-swapped. Keying the group makes the change
        // a replacement SwiftUI can cross-fade, in step with the card resizing.
        .id(state.selectedSection)
        .transition(.asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.19).delay(0.07)),
            removal: .opacity.animation(.easeIn(duration: 0.12))
        ))
    }
}

struct HomeNotchSection: View {
    @ObservedObject var state: JendelaState

    var body: some View {
        VStack(spacing: 13) {
            HStack(spacing: 12) {
                TrackArtwork(state: state, size: 62, corner: 15, symbolSize: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOW PLAYING")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.45))
                    Text(state.currentTrack.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(state.currentTrack.artist)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    Button { state.previousTrack() } label: {
                        Image(systemName: "backward.fill").frame(width: 30, height: 32).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Previous track")
                    Button { state.togglePlayPause() } label: {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill").frame(width: 30, height: 32).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(state.isPlaying ? "Pause" : "Play")
                    Button { state.nextTrack() } label: {
                        Image(systemName: "forward.fill").frame(width: 30, height: 32).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Next track")
                }.font(.caption)
            }
            .padding(12)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.07)).allowsHitTesting(false) }
            HStack(spacing: 8) {
                QuickAction(title: "Notes", symbol: "square.and.pencil") {
                    state.showNotes()
                }
                QuickAction(title: "Clipboard", symbol: "doc.on.clipboard") {
                    state.selectedSection = .clipboard
                }
                QuickAction(title: state.focusLabel, symbol: state.focusRunning ? "stop.fill" : "timer") {
                    state.toggleFocus()
                }
            }
        }
    }
}

/// Cover art for the current track, falling back to the accent gradient when
/// the player exposes none.
struct TrackArtwork: View {
    @ObservedObject var state: JendelaState
    let size: CGFloat
    let corner: CGFloat
    var symbolSize: CGFloat = 16

    var body: some View {
        Group {
            if let icon = state.musicIcon {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [state.appliedTheme.accentColor, state.appliedTheme.secondaryColor],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: state.isPlaying ? "waveform" : "music.note")
                        .font(.system(size: symbolSize, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct AmbientMusicIndicatorView: View {
    @ObservedObject var state: JendelaState

    private var track: NowPlayingMonitor.Track? { state.nowPlaying.track }

    var body: some View {
        Button {
            state.openNotch(.music)
        } label: {
            content
                .padding(.horizontal, state.ambientStyle == .artwork ? 0 : 10)
                .frame(width: width, height: 30)
                .background(.black.opacity(0.94), in: shape)
                .overlay { shape.stroke(.white.opacity(0.12), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .help(track.map { "\($0.title) — click for controls" } ?? "Click to open music controls")
    }

    private var shape: AnyShape {
        state.ambientStyle == .artwork ? AnyShape(Circle()) : AnyShape(Capsule())
    }

    private var width: CGFloat { state.ambientSize.width }

    @ViewBuilder
    private var content: some View {
        switch state.ambientStyle {
        case .artwork:
            AmbientArtwork(state: state)
        case .title:
            HStack(spacing: 6) {
                AmbientBars(state: state)
                Text(track?.title ?? "Not playing")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
        case .waveform, .none:
            HStack(spacing: 6) {
                AmbientBars(state: state)
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }
}

/// Cover art when the player gives us any, and the theme disc when it does not.
struct AmbientArtwork: View {
    @ObservedObject var state: JendelaState

    var body: some View {
        Group {
            if let icon = state.musicIcon {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [state.appliedTheme.accentColor, state.appliedTheme.secondaryColor],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
    }
}

/// Five bars. They only animate while something is playing *and* the machine is
/// not conserving power — a permanently animating menu-bar item is exactly the
/// kind of thing this app is supposed to avoid.
struct AmbientBars: View {
    @ObservedObject var state: JendelaState
    @State private var phase: CGFloat = 0

    private var animates: Bool { state.isPlaying && !state.conserving }
    private let heights: [CGFloat] = [5, 11, 8, 13, 6]

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, base in
                Capsule()
                    .fill(state.appliedTheme.accentColor)
                    .frame(width: 2, height: barHeight(index: index, base: base))
            }
        }
        .frame(height: 14)
        .onAppear { restart() }
        .onChange(of: animates) { _, _ in restart() }
    }

    private func barHeight(index: Int, base: CGFloat) -> CGFloat {
        guard animates else { return max(3, base * 0.45) }
        let offset = sin(phase + CGFloat(index) * 0.9)
        return max(3, base * (0.55 + 0.45 * offset))
    }

    private func restart() {
        guard animates else { return }
        phase = 0
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
            phase = .pi
        }
    }
}

struct ClipboardNotchSection: View {
    @ObservedObject var state: JendelaState
    @State private var hoveredID: ClipboardEntry.ID?
    @State private var copiedID: ClipboardEntry.ID?
    @State private var preview: ClipboardEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            searchField

            if state.visibleClipboardItems.isEmpty {
                emptyState
            } else {
                VStack(spacing: 6) {
                    ForEach(state.visibleClipboardItems) { item in
                        row(for: item)
                    }
                }
            }
        }
        .sheet(item: $preview) { item in
            ClipboardPreview(entry: item, state: state) { preview = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Clipboard").font(.headline)
                Text(captureStatus)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(state.clipboardAutoCapture ? Color.green : .white.opacity(0.38))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            iconButton(state.clipboardAutoCapture ? "pause.fill" : "play.fill",
                       help: state.clipboardAutoCapture ? "Pause capture" : "Resume capture") {
                state.clipboardAutoCapture.toggle()
            }
            iconButton("trash", help: "Clear unpinned items") { state.clearClipboard() }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.36))
            TextField("Search", text: $state.clipboardSearch)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !state.clipboardSearch.isEmpty {
                Button { state.clipboardSearch = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Image(systemName: state.clipboardSearch.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(.white.opacity(0.28))
            Text(state.clipboardSearch.isEmpty ? "Copy something to see it here" : "No matches")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.38))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    /// Each entry is a full row: a kind badge, two lines of context, and the
    /// actions revealed on hover. Click pastes, drag carries it to another app.
    private func row(for item: ClipboardEntry) -> some View {
        let hovered = hoveredID == item.id
        let copied = copiedID == item.id

        return HStack(spacing: 10) {
            ClipboardEntryThumbnail(entry: item, accent: state.appliedTheme.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .font(.system(size: 12))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(item.kindLabel)
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.4)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(.white.opacity(0.1), in: Capsule())
                    Text(item.subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if copied {
                Label("Copied", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.green)
                    .transition(.opacity)
            } else if hovered || item.pinned {
                Button { state.togglePin(item) } label: {
                    Image(systemName: item.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(item.pinned ? state.appliedTheme.accentColor : .white.opacity(0.5))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.pinned ? "Unpin" : "Pin")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background(
            hovered ? .white.opacity(0.12) : .white.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hoveredID = $0 ? item.id : nil }
        .onTapGesture {
            state.pasteClipboard(item)
            copiedID = item.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                if copiedID == item.id { copiedID = nil }
            }
        }
        .onDrag { ClipboardDragProvider.provider(for: item) }
        .onTapGesture(count: 2) { preview = item }
        .contextMenu {
            Button("Quick Look") { preview = item }
            Button("Copy") { state.pasteClipboard(item) }
            if item.kind != .image {
                Button("Copy as plain text") { state.pastePlain(item) }
            }
            Button(item.pinned ? "Unpin" : "Pin") { state.togglePin(item) }
            Divider()
            Button("Remove", role: .destructive) { state.removeClipboardItem(item) }
        }
        .help("Click to copy · double-click to preview · drag to another app")
    }

    private var captureStatus: String {
        guard state.clipboardAutoCapture else { return "Capture paused" }
        return state.conserving ? "Capturing · relaxed for battery" : "Capturing automatically"
    }
}

struct ClipboardEntryThumbnail: View {
    let entry: ClipboardEntry
    let accent: Color

    var body: some View {
        Group {
            if entry.kind == .image, let data = entry.data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: entry.symbol)
                    .foregroundStyle(accent)
            }
        }
        .frame(width: 26, height: 26)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Full-size look at a clipboard entry: the whole image, or the whole text
/// rather than the single truncated line the row can show.
struct ClipboardPreview: View {
    let entry: ClipboardEntry
    @ObservedObject var state: JendelaState
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: entry.symbol)
                    .foregroundStyle(state.appliedTheme.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.kindLabel)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(entry.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer()
                Button("Copy") { state.pasteClipboard(entry); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(state.appliedTheme.accentColor)
                Button("Done", action: dismiss).buttonStyle(.bordered)
            }
            .padding(14)

            Divider().overlay(.white.opacity(0.1))

            ScrollView {
                if entry.kind == .image, let data = entry.data, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .padding(14)
                } else {
                    Text(entry.title)
                        .font(.system(size: 12, design: entry.kind == .file ? .monospaced : .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }
        }
        .frame(width: 560, height: 460)
        .background(Color(hex: 0x141519))
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }
}

enum ClipboardDragProvider {
    static func provider(for entry: ClipboardEntry) -> NSItemProvider {
        let provider = NSItemProvider()
        if let data = entry.data, let typeIdentifier = entry.pasteboardType?.rawValue {
            provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
        } else {
            provider.registerObject(NSString(string: entry.title), visibility: .all)
        }
        return provider
    }
}

struct MusicNotchSection: View {
    @ObservedObject var state: JendelaState

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Music").font(.headline)
                    if state.musicHintIsWarning {
                        Button { state.resolveMusicPermission() } label: {
                            HStack(alignment: .top, spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(state.musicHint)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)
                                Image(systemName: "arrow.up.forward.app")
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Show me how to fix this")
                    } else {
                        Text(state.musicHint)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.42))
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button("Open") { state.openMusicProvider() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(state.appliedTheme.accentColor)
            }

            HStack(spacing: 7) {
                ForEach(MusicProvider.allCases) { provider in
                    Button {
                        state.musicProvider = provider
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: provider.symbol).font(.system(size: 13, weight: .semibold))
                            Text(provider.rawValue).font(.system(size: 8, weight: .semibold)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(state.musicProvider == provider ? state.appliedTheme.accentColor.opacity(0.22) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 11) {
                TrackArtwork(state: state, size: 42, corner: 9, symbolSize: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.currentTrack.title).font(.caption.weight(.semibold))
                    Text(state.musicProvider.rawValue).font(.caption2).foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Button { state.previousTrack() } label: { Image(systemName: "backward.fill").frame(width: 30, height: 32).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("Previous track")
                Button { state.togglePlayPause() } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill").frame(width: 30, height: 32).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(state.isPlaying ? "Pause" : "Play")
                Button { state.nextTrack() } label: { Image(systemName: "forward.fill").frame(width: 30, height: 32).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("Next track")
            }
        }
    }
}

struct SoundNotchSection: View {
    @ObservedObject var state: JendelaState

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Sound").font(.headline)
                Spacer()
                Text(state.audio.currentDeviceName)
                    .font(.caption2).foregroundStyle(.white.opacity(0.42)).lineLimit(1)
            }
            HStack(spacing: 12) {
                Button { state.audio.setMuted(!state.audio.isMuted) } label: {
                    Image(systemName: state.audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                        .foregroundStyle(state.audio.isMuted ? .orange : .blue)
                }
                .buttonStyle(.plain)
                .disabled(!state.audio.canSetMute)
                .accessibilityLabel(state.audio.isMuted ? "Unmute" : "Mute")
                Slider(
                    value: Binding(
                        get: { Double(state.audio.volume) },
                        set: { state.audio.setVolume(Float($0)) }
                    )
                )
                .disabled(!state.audio.canSetVolume)
                Text("\(Int(state.audio.volume * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 36)
            }
            HStack(spacing: 9) {
                ForEach(state.audio.devices.prefix(2)) { device in
                    Button { state.audio.selectDevice(device.id) } label: {
                        DeviceTile(
                            name: device.name,
                            detail: device.isDefault ? "Output" : "Switch to",
                            symbol: device.name.localizedCaseInsensitiveContains("airpod")
                                ? "airpodspro" : "laptopcomputer",
                            active: device.isDefault
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Picker("Output device", selection: Binding(
                get: { state.audio.devices.first(where: { $0.isDefault })?.id ?? 0 },
                set: { state.audio.selectDevice($0) }
            )) {
                ForEach(state.audio.devices) { device in Text(device.name).tag(device.id) }
            }.font(.caption)
            if let error = state.audio.error {
                Text(error).font(.caption2).foregroundStyle(.orange)
            } else if !state.audio.canSetVolume {
                Text("Use this device’s own volume controls.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct DiscordNotchSection: View {
    @ObservedObject var state: JendelaState

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Discord overlay").font(.headline)
                    Text(state.discordRunning ? "Discord is running" : "Discord is not running")
                        .font(.caption).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { state.openDiscord() } label: {
                    Text("Open Discord")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(.white.opacity(0.1), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Circle().fill(state.discordRunning ? Color.green : .gray).frame(width: 8, height: 8)
            }

            HStack(spacing: 8) {
                CallToggle(title: "Camera", symbol: state.discordCameraOn ? "video.fill" : "video.slash.fill", active: state.discordCameraOn) {
                    state.discordCameraOn.toggle()
                }
                CallToggle(title: "Share", symbol: "rectangle.on.rectangle", active: state.discordSharingOn) {
                    state.discordSharingOn.toggle()
                }
                CallToggle(title: "Keep up", symbol: state.discordOverlayPinned ? "pin.fill" : "pin", active: state.discordOverlayPinned) {
                    state.discordOverlayPinned.toggle()
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "number")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                TextField("Channel label", text: $state.discordChannelName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                Slider(value: $state.discordOverlayOpacity, in: 0.4...1)
                Text("\(Int(state.discordOverlayOpacity * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 34)
            }

            Text("The overlay floats above other apps on every Space, and can be dragged and resized. Camera and share state is set here — reading it from Discord needs a registered Discord app and your authorisation.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.36))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}


struct DesktopNoteView: View {
    @ObservedObject var state: JendelaState
    let note: NoteRecord
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .top) {
            RichNoteEditor(
                id: note.id,
                onChange: { text in state.noteChanged(note.id, text: text.string) },
                onHide: { state.noteVisible = false },
                onNew: { state.addNote() },
                onDelete: { state.deleteNote(note.id) }
            )
            .padding(.horizontal, 6)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // No title bar. A grip appears on hover purely so there is somewhere
            // to drag that is not the text — clicking the text must place the
            // caret, not move the window.
            if hovering {
                Capsule()
                    .fill(.white.opacity(0.28))
                    .frame(width: 34, height: 3.5)
                    .padding(.top, 4)
                    .transition(.opacity)
            }
        }
        .background(
            Color(hex: 0x141519).opacity(0.94),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(hovering ? 0.16 : 0.07))
                .allowsHitTesting(false)
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}


struct MenuBarView: View {
    @ObservedObject var state: JendelaState
    let delegate: JendelaAppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Jendela Studio") { delegate.showStudio(using: openWindow) }
        Button(state.notchExpanded ? "Collapse Notch Hub" : "Expand Notch Hub") { delegate.toggleNotch() }
        Button(state.noteVisible ? "Hide Desktop Note" : "Show Desktop Note") { delegate.toggleNote() }
        Button(state.hideNotch ? "Show the Notch" : "Hide the Notch") { state.setHideNotch(!state.hideNotch) }
        Divider()
        Picker("Battery Saver", selection: $state.batterySaverMode) {
            ForEach(JendelaState.BatterySaverMode.allCases) { Text($0.label).tag($0) }
        }
        Divider()
        Button("Quit Jendela") { NSApp.terminate(nil) }
    }
}

struct ControlCard<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    @ViewBuilder let content: Content

    init(title: String, subtitle: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption2).foregroundStyle(.white.opacity(0.42))
                }
            }
            content
                .font(.caption)
        }
        .padding(14)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }
}

struct QuickAction: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 15))
                Text(title).font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct DeviceTile: View {
    let name: String
    let detail: String
    let symbol: String
    let active: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.caption.weight(.semibold)).lineLimit(1)
                Text(detail).font(.caption2).foregroundStyle(.white.opacity(0.38)).lineLimit(1)
            }
            Spacer(minLength: 4)
            if active { Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue) }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(active ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct CallToggle: View {
    let title: String
    let symbol: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(active ? Color.indigo.opacity(0.7) : .white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}

struct NotchPreview: View {
    @ObservedObject var state: JendelaState

    var body: some View {
        Button {
            state.toggleHub()
        } label: {
            if state.notchExpanded {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(colors: [state.appliedTheme.accentColor, state.appliedTheme.secondaryColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 23, height: 23)
                            .overlay { Image(systemName: "sparkles").font(.system(size: 8, weight: .bold)) }
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Jendela.").font(.system(size: 9, weight: .bold, design: .rounded))
                            Text("Desktop is calm").font(.system(size: 6)).foregroundStyle(.white.opacity(0.46))
                        }
                        Spacer()
                        Circle().fill(.green).frame(width: 5, height: 5)
                        Text("Battery aware").font(.system(size: 6, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                        Image(systemName: "chevron.up").font(.system(size: 7, weight: .bold)).foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 36)

                    HStack(spacing: 5) {
                        ForEach(JendelaState.NotchSection.allCases) { section in
                            Image(systemName: section.symbol)
                                .font(.system(size: 8, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 20)
                                .background(section == state.selectedSection ? .white.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(section == state.selectedSection ? .white : .white.opacity(0.35))
                        }
                    }
                    .padding(.horizontal, 10)

                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(LinearGradient(colors: [Color(hex: 0xE37394), Color(hex: 0x6B4CD6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 42, height: 42)
                            .overlay { Image(systemName: "moon.stars.fill").font(.caption) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NOW PLAYING").font(.system(size: 5, weight: .bold)).tracking(0.8).foregroundStyle(.white.opacity(0.4))
                            Text(state.currentTrack.title).font(.system(size: 10, weight: .bold, design: .rounded))
                            Text(state.currentTrack.artist).font(.system(size: 6)).foregroundStyle(.white.opacity(0.42))
                        }
                        Spacer()
                        Image(systemName: "backward.fill")
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        Image(systemName: "forward.fill")
                    }
                    .font(.system(size: 7))
                    .padding(9)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
                    .padding(9)
                }
                .frame(width: 330, height: 140, alignment: .top)
                .background(Color(hex: 0x111216).opacity(0.98), in: UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
                .overlay { UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18).stroke(.white.opacity(0.12)) }
                .shadow(color: .black.opacity(0.42), radius: 12, y: 8)
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.black)
                    .frame(width: 132, height: 24)
                    .overlay(alignment: .bottom) {
                        Capsule()
                            .fill(.white.opacity(0.16))
                            .frame(width: 22, height: 2)
                            .offset(y: -4)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.white.opacity(configuration.isPressed ? 0.14 : 0.08), in: RoundedRectangle(cornerRadius: 9))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
