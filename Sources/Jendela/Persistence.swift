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

enum SettingsStore {
    private static let queue = DispatchQueue(label: "com.widgetmac.settings")

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jendela", isDirectory: true)
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
