import Foundation

/// Every user-changeable value in one snapshot. Replaces the per-property
/// `didSet` writers (which fired a `UserDefaults` write on every keystroke)
/// with a single debounced save.
struct JendelaSettings: Codable, Equatable {
    var quickNoteText = "Today\n\n• Shape the desktop companion\n• Keep it calm and lightweight\n• Test the Discord mini view"
    var appliedTemplateID = "midnight"
    var selectedTemplateID = "midnight"
    var notchSize = "Standard"
    var expandOnHover = true
    var showTrackInCompact = true
    var showMusicIndicator = true
    var clipboardAutoCapture = true
    var skipConcealedClipboard = true
    var clipboardLimit = 100
    var launchAtLogin = false
    var hasOnboarded = false
    var hotKeys: [String: HotKeyBinding] = [:]
    var musicProvider = "Music"
    var discordPipEnabled = true
    var batterySaverMode = "auto"
    var noteVisible = false
    var selectedSection = "Home"
    var studioSection = "Themes"
    var selectedCategory = "All"
    var syncWallpaperWithTheme = false
    var focusMinutes = 25
    var showNotchHandle = false
    var hideNotch = false
    var ambientStyle = "waveform"
    var musicIconStyle = "automatic"
    var hubWidth: Double = 438
    var noteFrame: [Double] = []
    var notes: [NoteRecord] = []
    var discordOverlayFrame: [Double] = []
    var discordOverlayPinned = false
    var discordOverlayOpacity: Double = 0.94
    var discordChannelName = ""
    var enabledSections: [String] = []
    var photos: [String] = []
    var photoRotationMinutes = 30
    var originalWallpapers: [String] = []

}

/// See the initialiser's note: lenient decoding is what keeps an upgrade
/// from resetting existing preferences.
extension JendelaSettings {
    /// Decoded leniently, key by key.
    ///
    /// Swift's synthesised decoder throws when *any* key is absent, even for
    /// properties with defaults. That would mean every newly added setting
    /// silently reset every existing user's preferences on upgrade, so each
    /// field falls back to its default instead.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = JendelaSettings()
        quickNoteText = (try? c.decodeIfPresent(String.self, forKey: .quickNoteText)) ?? nil ?? fallback.quickNoteText
        appliedTemplateID = (try? c.decodeIfPresent(String.self, forKey: .appliedTemplateID)) ?? nil ?? fallback.appliedTemplateID
        selectedTemplateID = (try? c.decodeIfPresent(String.self, forKey: .selectedTemplateID)) ?? nil ?? fallback.selectedTemplateID
        notchSize = (try? c.decodeIfPresent(String.self, forKey: .notchSize)) ?? nil ?? fallback.notchSize
        expandOnHover = (try? c.decodeIfPresent(Bool.self, forKey: .expandOnHover)) ?? nil ?? fallback.expandOnHover
        showTrackInCompact = (try? c.decodeIfPresent(Bool.self, forKey: .showTrackInCompact)) ?? nil ?? fallback.showTrackInCompact
        showMusicIndicator = (try? c.decodeIfPresent(Bool.self, forKey: .showMusicIndicator)) ?? nil ?? fallback.showMusicIndicator
        clipboardAutoCapture = (try? c.decodeIfPresent(Bool.self, forKey: .clipboardAutoCapture)) ?? nil ?? fallback.clipboardAutoCapture
        skipConcealedClipboard = (try? c.decodeIfPresent(Bool.self, forKey: .skipConcealedClipboard)) ?? nil ?? fallback.skipConcealedClipboard
        clipboardLimit = (try? c.decodeIfPresent(Int.self, forKey: .clipboardLimit)) ?? nil ?? fallback.clipboardLimit
        launchAtLogin = (try? c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? nil ?? fallback.launchAtLogin
        musicProvider = (try? c.decodeIfPresent(String.self, forKey: .musicProvider)) ?? nil ?? fallback.musicProvider
        discordPipEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .discordPipEnabled)) ?? nil ?? fallback.discordPipEnabled
        batterySaverMode = (try? c.decodeIfPresent(String.self, forKey: .batterySaverMode)) ?? nil ?? fallback.batterySaverMode
        noteVisible = (try? c.decodeIfPresent(Bool.self, forKey: .noteVisible)) ?? nil ?? fallback.noteVisible
        selectedSection = (try? c.decodeIfPresent(String.self, forKey: .selectedSection)) ?? nil ?? fallback.selectedSection
        studioSection = (try? c.decodeIfPresent(String.self, forKey: .studioSection)) ?? nil ?? fallback.studioSection
        selectedCategory = (try? c.decodeIfPresent(String.self, forKey: .selectedCategory)) ?? nil ?? fallback.selectedCategory
        syncWallpaperWithTheme = (try? c.decodeIfPresent(Bool.self, forKey: .syncWallpaperWithTheme)) ?? nil ?? fallback.syncWallpaperWithTheme
        focusMinutes = (try? c.decodeIfPresent(Int.self, forKey: .focusMinutes)) ?? nil ?? fallback.focusMinutes
        showNotchHandle = (try? c.decodeIfPresent(Bool.self, forKey: .showNotchHandle)) ?? nil ?? fallback.showNotchHandle
        hideNotch = (try? c.decodeIfPresent(Bool.self, forKey: .hideNotch)) ?? nil ?? fallback.hideNotch
        ambientStyle = (try? c.decodeIfPresent(String.self, forKey: .ambientStyle)) ?? nil ?? fallback.ambientStyle
        musicIconStyle = (try? c.decodeIfPresent(String.self, forKey: .musicIconStyle)) ?? nil ?? fallback.musicIconStyle
        hubWidth = (try? c.decodeIfPresent(Double.self, forKey: .hubWidth)) ?? nil ?? fallback.hubWidth
        noteFrame = (try? c.decodeIfPresent([Double].self, forKey: .noteFrame)) ?? nil ?? fallback.noteFrame
        notes = (try? c.decodeIfPresent([NoteRecord].self, forKey: .notes)) ?? nil ?? fallback.notes
        discordOverlayFrame = (try? c.decodeIfPresent([Double].self, forKey: .discordOverlayFrame)) ?? nil ?? fallback.discordOverlayFrame
        discordOverlayPinned = (try? c.decodeIfPresent(Bool.self, forKey: .discordOverlayPinned)) ?? nil ?? fallback.discordOverlayPinned
        discordOverlayOpacity = (try? c.decodeIfPresent(Double.self, forKey: .discordOverlayOpacity)) ?? nil ?? fallback.discordOverlayOpacity
        discordChannelName = (try? c.decodeIfPresent(String.self, forKey: .discordChannelName)) ?? nil ?? fallback.discordChannelName
        enabledSections = (try? c.decodeIfPresent([String].self, forKey: .enabledSections)) ?? nil ?? fallback.enabledSections
        photos = (try? c.decodeIfPresent([String].self, forKey: .photos)) ?? nil ?? fallback.photos
        photoRotationMinutes = (try? c.decodeIfPresent(Int.self, forKey: .photoRotationMinutes)) ?? nil ?? fallback.photoRotationMinutes
        originalWallpapers = (try? c.decodeIfPresent([String].self, forKey: .originalWallpapers)) ?? nil ?? fallback.originalWallpapers
    }
}


enum SettingsStore {
    private static let queue = DispatchQueue(label: "com.widgetmac.settings")

    static var fileURL: URL {
        let base = SupportDirectory.root
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("settings.json")
    }

    static func load() -> JendelaSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(JendelaSettings.self, from: data)
        else { return JendelaSettings() }
        return decoded
    }

    /// Off the main thread — settings are saved on a debounce, never in a hot path.
    static func save(_ settings: JendelaSettings) {
        let url = fileURL
        queue.async {
            guard let data = try? JSONEncoder().encode(settings) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
