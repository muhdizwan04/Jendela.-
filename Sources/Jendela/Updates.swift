import AppKit
import Foundation

/// Checks a small JSON manifest for a newer build.
///
/// Notification, not silent installation: replacing a running app in place
/// needs Sparkle's helper and an EdDSA-signed appcast, which is a drop-in
/// upgrade once there is somewhere to host it. Until then this tells the user
/// plainly and sends them to the download.
///
/// Checked at most once a day, and never on a timer — on launch and when asked.
@MainActor
final class Updates: ObservableObject {
    struct Release: Equatable {
        var version: String
        var build: Int
        var url: URL
        var notes: String?
        var minimumSystem: String?
        var publishedAt: Date?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// Overridable so a build can point at a staging manifest.
    static var feedURL: URL? {
        if let custom = ProcessInfo.processInfo.environment["JENDELA_FEED_URL"],
           let url = URL(string: custom) { return url }
        return URL(string: "https://jendela.app/appcast.json")
    }

    private static let lastCheckKey = "lastUpdateCheck"
    private var lastCheck: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastCheckKey) }
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
    }

    /// Called on launch. Skips if it already looked today, so starting the app
    /// ten times does not mean ten requests.
    func checkIfDue() {
        if let last = lastCheck, Date().timeIntervalSince(last) < 24 * 3600 { return }
        check()
    }

    func check() {
        guard let url = Self.feedURL else {
            state = .failed("No update feed configured.")
            return
        }
        state = .checking
        lastCheck = Date()

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let error {
                        self.state = .failed(error.localizedDescription)
                        return
                    }
                    guard let data,
                          let release = Updates.parse(data)
                    else {
                        self.state = .failed("The update feed could not be read.")
                        return
                    }
                    self.state = Updates.isNewer(release) ? .available(release) : .upToDate
                }
            }
        }.resume()
    }

    func download() {
        guard case .available(let release) = state else { return }
        NSWorkspace.shared.open(release.url)
    }

    // MARK: - Parsing and comparison

    static func parse(_ data: Data) -> Release? {
        struct Manifest: Decodable {
            var version: String
            var build: Int
            var url: String
            var notes: String?
            var minimumSystemVersion: String?
            var publishedAt: String?
        }
        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              let url = URL(string: manifest.url)
        else { return nil }

        return Release(
            version: manifest.version,
            build: manifest.build,
            url: url,
            notes: manifest.notes,
            minimumSystem: manifest.minimumSystemVersion,
            publishedAt: manifest.publishedAt.flatMap {
                ISO8601DateFormatter().date(from: $0)
            }
        )
    }

    static func isNewer(_ release: Release, thanVersion version: String? = nil, build: Int? = nil) -> Bool {
        let currentVersion = version ?? Self.currentVersion
        let currentBuild = build ?? Self.currentBuild

        // Build number wins when both sides have one: it is monotonic, whereas
        // marketing versions get re-cut and re-tagged.
        if release.build > 0 && currentBuild > 0 {
            return release.build > currentBuild
        }
        return compare(release.version, currentVersion) == .orderedDescending
    }

    /// Numeric, component by component, so 1.10 is correctly newer than 1.9 —
    /// a plain string comparison gets that backwards.
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
