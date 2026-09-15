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
    var clipboardExcludedApps: [String] = []
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

enum SettingsStore {
    private static let queue = DispatchQueue(label: "com.widgetmac.settings")

    static var fileURL: URL {
        let base = SupportDirectory.root
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("settings.json")
    }

    /// Loads, filling in anything the stored file predates.
    ///
    /// Swift's synthesised decoder throws when any key is absent, even for
    /// properties with defaults, so a settings file written by an older build
    /// would reset every preference. Rather than hand-writing a lenient
    /// decoder — which silently goes stale the moment a field is added, as it
    /// did — the stored object is merged over the defaults and then decoded
    /// normally. Adding a property needs no further work.
    /// Whether the last `load()` read a real settings file rather than falling
    /// back to defaults. Anything destructive keyed off the loaded values — such
    /// as deleting note files with no matching record — must check this, since
    /// an unreadable file is otherwise indistinguishable from a first run.
    nonisolated(unsafe) private(set) static var loadedFromDisk = false

    static func load() -> JendelaSettings {
        loadedFromDisk = false
        guard let data = try? Data(contentsOf: fileURL) else { return JendelaSettings() }

        guard let defaults = try? JSONSerialization.jsonObject(
                with: JSONEncoder().encode(JendelaSettings())) as? [String: Any],
              let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (try? JSONDecoder().decode(JendelaSettings.self, from: data)) ?? JendelaSettings()
        }

        let merged = defaults.merging(stored) { _, fromFile in fromFile }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let decoded = try? JSONDecoder().decode(JendelaSettings.self, from: mergedData)
        else { return JendelaSettings() }
        loadedFromDisk = true
        return decoded
    }

    /// Blocks until pending writes land. Used before termination and by tests.
    static func flush() { queue.sync {} }

    @available(*, deprecated, renamed: "flush()")
    static func flushForTesting() { flush() }

    /// Off the main thread — settings are saved on a debounce, never in a hot path.
    static func save(_ settings: JendelaSettings) {
        let url = fileURL
        queue.async {
            guard let data = try? JSONEncoder().encode(settings) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
