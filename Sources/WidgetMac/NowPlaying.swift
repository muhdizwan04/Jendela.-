import AppKit
import Combine
import Foundation

/// Real now-playing metadata, with no polling at all.
///
/// Music.app and Spotify both broadcast a distributed notification on every
/// track or state change, carrying the title, artist, album and player state.
/// We listen for those and only fall back to a one-shot AppleScript query on
/// an explicit event (the hub opening), never on a timer.
@MainActor
final class NowPlayingMonitor: ObservableObject {
    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String
        var isPlaying: Bool
        var source: MusicProvider
    }

    @Published private(set) var track: Track?
    /// YouTube Music is a web page: no notifications, no scripting interface,
    /// and media keys give no feedback. Its play state is therefore tracked
    /// locally from the commands we send, and its title is read from the
    /// browser tab. Optimistic, but far better than reporting "nothing playing"
    /// while the user can plainly hear it.
    @Published var youtubePlaying = false
    /// Cover art, when the player exposes any. Fetched only on track change.
    @Published private(set) var artwork: NSImage?
    /// True when the browser refused to run our JavaScript. That is the only
    /// route to cover art and real play state for YouTube Music, so the UI
    /// offers the one-line fix rather than silently degrading.
    @Published private(set) var youtubeScriptBlocked = false
    /// Set when macOS refuses our Apple Events, so the UI can say so instead of
    /// silently lying about the transport state.
    @Published private(set) var automationDenied = false

    private static let scriptQueue = DispatchQueue(label: "com.widgetmac.applescript")

    init() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let fields = NowPlayingMonitor.fields(from: note.userInfo)
            MainActor.assumeIsolated { self?.ingest(fields, from: .appleMusic) }
        }
        center.addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let fields = NowPlayingMonitor.fields(from: note.userInfo)
            MainActor.assumeIsolated { self?.ingest(fields, from: .spotify) }
        }
    }

    deinit { DistributedNotificationCenter.default().removeObserver(self) }

    /// Notifications aren't `Sendable`; reduce to plain strings before hopping.
    nonisolated static func fields(from userInfo: [AnyHashable: Any]?) -> [String: String] {
        guard let userInfo else { return [:] }
        var out: [String: String] = [:]
        for key in ["Name", "Artist", "Album", "Player State"] {
            if let value = userInfo[key] as? String { out[key] = value }
        }
        return out
    }

    /// Pulls cover art for the current track. Music hands back raw image data;
    /// Spotify hands back a URL. Called only when the track changes.
    func refreshArtwork(provider: MusicProvider) {
        guard provider != .youtube else { artwork = nil; return }
        let isMusic = provider == .appleMusic
        let source = isMusic
            ? "tell application \"Music\" to if player state is not stopped then return data of artwork 1 of current track"
            : "tell application \"Spotify\" to if player state is not stopped then return artwork url of current track"
        Self.scriptQueue.async { [weak self] in
            var error: NSDictionary?
            let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)
            var image: NSImage?
            if isMusic, let data = descriptor?.data, !data.isEmpty {
                image = NSImage(data: data)
            } else if !isMusic, let urlString = descriptor?.stringValue,
                      let url = URL(string: urlString),
                      let data = try? Data(contentsOf: url) {
                image = NSImage(data: data)
            }
            let resolved = image
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.artwork = resolved }
            }
        }
    }

    private func ingest(_ info: [String: String], from source: MusicProvider) {
        guard !info.isEmpty else { return }
        let state = info["Player State"] ?? ""
        guard state != "Stopped" else {
            if track?.source == source { track = nil }
            return
        }
        let previousTitle = track?.title
        track = Track(
            title: info["Name"] ?? "Unknown track",
            artist: info["Artist"] ?? "",
            album: info["Album"] ?? "",
            isPlaying: state == "Playing",
            source: source
        )
        if track?.title != previousTitle { refreshArtwork(provider: source) }
    }

    /// One-shot query, used when the hub opens so we show something even if no
    /// notification has arrived since launch. Runs off the main thread — Apple
    /// Events block, and Music.app may need to launch to answer.
    func refresh(provider: MusicProvider) {
        guard provider != .youtube else { return }
        let app = provider == .appleMusic ? "Music" : "Spotify"
        guard NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == (provider == .appleMusic ? "com.apple.Music" : "com.spotify.client")
        }) else { return }

        let source = """
        tell application "\(app)"
            if player state is stopped then return "stopped"
            return (name of current track) & "\u{1F}" & (artist of current track) \
                & "\u{1F}" & (album of current track) & "\u{1F}" & (player state as text)
        end tell
        """
        Self.scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let denied = (error?["NSAppleScriptErrorNumber"] as? Int).map { $0 == -1743 } ?? false
            let value = result?.stringValue
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if denied { self.automationDenied = true; return }
                    self.automationDenied = false
                    guard let value, value != "stopped" else { return }
                    let parts = value.components(separatedBy: "\u{1F}")
                    guard parts.count == 4 else { return }
                    self.track = Track(
                        title: parts[0],
                        artist: parts[1],
                        album: parts[2],
                        isPlaying: parts[3].lowercased() == "playing",
                        source: provider
                    )
                }
            }
        }
    }

    /// Browsers that expose tabs to AppleScript, with the property names they
    /// use for a tab's title.
    private static let browsers: [(bundle: String, app: String, titleProperty: String)] = [
        ("com.google.Chrome", "Google Chrome", "title"),
        ("com.brave.Browser", "Brave Browser", "title"),
        ("com.microsoft.edgemac", "Microsoft Edge", "title"),
        ("company.thebrowser.Browser", "Arc", "title"),
        ("com.apple.Safari", "Safari", "name")
    ]

    /// Reads YouTube Music straight out of the page.
    ///
    /// Two routes, in order. Running JavaScript in the tab gives the real
    /// title, artist, cover art *and* paused state - everything the other
    /// players publish. It needs "Allow JavaScript from Apple Events" enabled
    /// in the browser, so when that is off we fall back to parsing the tab
    /// title, which always works but carries no artwork and no play state.
    /// Brings the existing YouTube Music tab forward instead of opening a new
    /// one, and reports whether it found it.
    @discardableResult
    func focusYouTubeTab() -> Bool {
        for browser in Self.browsers where NSWorkspace.shared.runningApplications
            .contains(where: { $0.bundleIdentifier == browser.bundle }) {
            let source = """
            tell application "\(browser.app)"
                repeat with w in windows
                    set i to 0
                    repeat with t in tabs of w
                        set i to i + 1
                        if URL of t contains "music.youtube.com" then
                            set active tab index of w to i
                            set index of w to 1
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end tell
            return "none"
            """
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if result?.stringValue == "ok" { return true }
        }
        return false
    }

    func refreshYouTube() {
        let candidates = Self.browsers.filter { browser in
            NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == browser.bundle }
        }
        guard !candidates.isEmpty else {
            if track?.source == .youtube { clearYouTube() }
            return
        }

        Self.scriptQueue.async { [weak self] in
            var payload: String?
            var fallbackTitle: String?

            // Single quotes only: this is embedded in an AppleScript string.
            let js = "(function(){"
                + "var v=document.querySelector('video'),"
                + "t=document.querySelector('.title.ytmusic-player-bar'),"
                + "b=document.querySelector('.byline.ytmusic-player-bar'),"
                + "i=document.querySelector('.image.ytmusic-player-bar');"
                + "return [t?t.textContent.trim():'',b?b.textContent.trim():'',"
                + "i?i.src:'',(v&&!v.paused)?'1':'0'].join(String.fromCharCode(31));})()"

            for browser in candidates {
                let runner = browser.app == "Safari"
                    ? "do JavaScript \"" + js + "\" in t"
                    : "execute t javascript \"" + js + "\""
                let source = """
                tell application "\(browser.app)"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if URL of t contains "music.youtube.com" then
                                try
                                    return \(runner)
                                on error
                                    return \(browser.titleProperty) of t
                                end try
                            end if
                        end repeat
                    end repeat
                end tell
                return ""
                """
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                guard let value = result?.stringValue, !value.isEmpty else { continue }
                if value.contains("\u{1F}") { payload = value } else { fallbackTitle = value }
                break
            }

            let resolvedPayload = payload
            let resolvedTitle = fallbackTitle
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.youtubeScriptBlocked = (resolvedPayload == nil && resolvedTitle != nil)
                    if let resolvedPayload {
                        self.applyYouTube(payload: resolvedPayload)
                    } else {
                        self.applyYouTube(title: resolvedTitle)
                    }
                }
            }
        }
    }

    /// Drives the YouTube Music page directly, which is the only way to be sure
    /// the command lands on the browser. Media keys go to whichever app macOS
    /// considers "now playing" — if Music.app is open, it takes them, which is
    /// why pressing play on the YouTube tab started Music instead.
    /// Returns false when the browser refuses to run scripts.
    func controlYouTube(_ action: String) -> Bool {
        let candidates = Self.browsers.filter { browser in
            NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == browser.bundle }
        }
        guard !candidates.isEmpty else { return false }

        let selector: String
        switch action {
        case "previous track": selector = ".previous-button"
        case "next track": selector = ".next-button"
        default: selector = "#play-pause-button"
        }
        let js = "(function(){var b=document.querySelector('" + selector
            + "');if(b){b.click();return 'ok'}return 'no'})()"

        var handled = false
        for browser in candidates {
            let runner = browser.app == "Safari"
                ? "do JavaScript \"" + js + "\" in t"
                : "execute t javascript \"" + js + "\""
            let source = """
            tell application "\(browser.app)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if URL of t contains "music.youtube.com" then
                            try
                                return \(runner)
                            on error
                                return "blocked"
                            end try
                        end if
                    end repeat
                end repeat
            end tell
            return "none"
            """
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let value = result?.stringValue ?? "none"
            if value == "ok" { handled = true; break }
            if value == "blocked" { youtubeScriptBlocked = true; break }
        }
        return handled
    }

    private func clearYouTube() {
        track = nil
        artwork = nil
    }

    /// The rich path: title, artist, artwork and real paused state.
    private func applyYouTube(payload: String) {
        let parts = payload.components(separatedBy: "\\u{1F}")
        guard parts.count == 4, !parts[0].isEmpty else { clearYouTube(); return }

        let playing = parts[3] == "1"
        youtubePlaying = playing
        let changed = track?.title != parts[0]
        track = Track(
            title: parts[0],
            artist: parts[1],
            album: "",
            isPlaying: playing,
            source: .youtube
        )

        guard changed else { return }
        guard let url = URL(string: parts[2]), !parts[2].isEmpty else { artwork = nil; return }
        Self.scriptQueue.async { [weak self] in
            let data = try? Data(contentsOf: url)
            let image = data.flatMap(NSImage.init(data:))
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.artwork = image }
            }
        }
    }

    /// The fallback path: only the tab title is available.
    private func applyYouTube(title: String?) {
        guard let raw = title, !raw.isEmpty else { clearYouTube(); return }

        // Titles look like "Song - Artist - YouTube Music" or, as YouTube Music
        // actually writes it, "Song | YouTube Music".
        var text = raw
        for suffix in [" - YouTube Music", " | YouTube Music", " — YouTube Music"] {
            if text.hasSuffix(suffix) { text = String(text.dropLast(suffix.count)) }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "YouTube Music" else { clearYouTube(); return }

        let parts = text.components(separatedBy: " - ")
        // With no play state available, a loaded track is assumed to be playing;
        // our own play/pause toggles it from there. Reporting "not playing"
        // while the user can hear it is the worse guess.
        if track?.source != .youtube { youtubePlaying = true }
        track = Track(
            title: parts.first ?? text,
            artist: parts.count > 1 ? parts.dropFirst().joined(separator: " - ") : "YouTube Music",
            album: "",
            isPlaying: youtubePlaying,
            source: .youtube
        )
        artwork = nil
    }

    func command(_ command: String, provider: MusicProvider) {
        guard provider != .youtube else { return }
        let app = provider == .appleMusic ? "Music" : "Spotify"
        let source = "tell application \"\(app)\" to \(command)"
        Self.scriptQueue.async {
            var error: NSDictionary?
            _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let denied = (error?["NSAppleScriptErrorNumber"] as? Int).map { $0 == -1743 } ?? false
            if denied {
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.automationDenied = true }
                }
            }
        }
    }
}
