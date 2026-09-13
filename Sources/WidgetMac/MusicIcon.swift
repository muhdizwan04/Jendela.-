import AppKit
import Foundation

/// What to draw where the cover art goes.
enum MusicIconStyle: String, CaseIterable, Identifiable {
    /// Cover art when the player gives us any, the player's own app icon when
    /// it does not. The sensible default.
    case automatic
    /// Always the player's app icon, even when art is available.
    case appIcon
    /// An image you chose.
    case custom
    /// The accent gradient with a note on it.
    case accent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Album art"
        case .appIcon: "App icon"
        case .custom: "Custom"
        case .accent: "Colour"
        }
    }

    var detail: String {
        switch self {
        case .automatic: "Cover art when available, otherwise the player's icon"
        case .appIcon: "Always show which app is playing"
        case .custom: "Pick your own image"
        case .accent: "A plain accent tile"
        }
    }
}

/// Resolves the icon shown alongside a track.
///
/// Player logos are read from the installed application rather than bundled as
/// image assets: it is always the real, current icon, it costs nothing to keep
/// up to date, and it avoids shipping other companies' trademarks inside this
/// app.
@MainActor
enum MusicIconStore {
    /// Icons are looked up once and reused. Main-actor isolated because it is
    /// only ever read while drawing.
    private static var cache: [String: NSImage] = [:]

    static var customURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WidgetMac", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("music-icon.png")
    }

    static func custom() -> NSImage? {
        guard FileManager.default.fileExists(atPath: customURL.path) else { return nil }
        return NSImage(contentsOf: customURL)
    }

    /// Imports a chosen image, downscaled once so it is never resized while
    /// drawing.
    @discardableResult
    static func importCustom(from source: URL) -> Bool {
        guard let image = NSImage(contentsOf: source),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return false }

        let edge: CGFloat = 256
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let scale = min(1, edge / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        guard let context = CGContext(
            data: nil, width: Int(target.width), height: Int(target.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: target))

        guard let scaled = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
        else { return false }
        try? data.write(to: customURL, options: .atomic)
        cache.removeValue(forKey: "custom")
        return true
    }

    static func removeCustom() {
        try? FileManager.default.removeItem(at: customURL)
    }

    /// The player's real application icon.
    static func appIcon(for provider: MusicProvider) -> NSImage? {
        if let cached = cache[provider.rawValue] { return cached }
        guard let url = applicationURL(for: provider) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 128, height: 128)
        cache[provider.rawValue] = icon
        return icon
    }

    private static func applicationURL(for provider: MusicProvider) -> URL? {
        switch provider {
        case .appleMusic:
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music")
        case .spotify:
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client")
        case .youtube:
            // YouTube Music has no app of its own; whichever browser would open
            // it is the honest thing to show.
            guard let site = URL(string: "https://music.youtube.com") else { return nil }
            return NSWorkspace.shared.urlForApplication(toOpen: site)
        }
    }
}
