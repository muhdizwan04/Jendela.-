import AppKit
import Foundation

/// The slice of app state the desktop widgets render.
///
/// Widgets run in a separate process, so the app writes this snapshot whenever
/// the underlying data changes and asks WidgetKit to reload. Nothing polls: the
/// widget only does work when it is told there is something new, which is the
/// whole reason to move desktop widgets onto WidgetKit in the first place.
struct WidgetSnapshot: Codable, Equatable {
    struct Clip: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var kind: String
        var pinned: Bool
    }

    var note: String = ""
    var clips: [Clip] = []
    var themeName: String = "Ember Focus"
    var startHex: UInt32 = 0x1C1512
    var endHex: UInt32 = 0x3A1C0E
    var accentHex: UInt32 = 0xFF5A1F
    var secondaryHex: UInt32 = 0xFFAE6A
    /// File names inside `PhotoStore.directory`.
    var photos: [String] = []
    /// How long each photo stays up before the next. The rotation is baked into
    /// the widget timeline, so it costs no extension wakeups.
    var photoRotationMinutes: Int = 30
    var updated: Date = .distantPast

    static let placeholder = WidgetSnapshot(
        note: "Today\n\n• Shape the desktop companion\n• Keep it calm",
        clips: [
            .init(id: "1", title: "A quiet desktop is a productive desktop.", kind: "text", pinned: true),
            .init(id: "2", title: "https://developer.apple.com/design/", kind: "text", pinned: false),
            .init(id: "3", title: "Screenshot 2026-09-10.png", kind: "image", pinned: false)
        ],
        updated: .now
    )
}

/// Photos live as files beside the snapshot so the widget reads them directly,
/// rather than carrying image bytes through JSON.
enum PhotoStore {
    /// Longest edge kept on import. A desktop widget is at most ~364pt, so
    /// 1400px is generous at 2x while keeping files small - the downscale
    /// happens once here instead of on every widget render.
    static let maxEdge: CGFloat = 1400

    static var directory: URL {
        let url = SharedStore.directory.appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Resolves a stored photo name, or nil if it is not one.
    ///
    /// Names are UUIDs when written, but they go out to the settings file and
    /// the shared snapshot and come back again. Anything that is not a single
    /// file name is refused, so a hand-edited list cannot point `remove` at a
    /// file outside this directory.
    static func url(for name: String) -> URL? {
        guard !name.isEmpty, !name.hasPrefix("."),
              !name.contains("/"), !name.contains("\\"),
              name == (name as NSString).lastPathComponent
        else { return nil }
        return directory.appendingPathComponent(name)
    }

    static func image(named name: String) -> NSImage? {
        guard let url = url(for: name) else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Drops names whose files are gone, so a deleted photo cannot leave the
    /// widget pointing at nothing.
    static func existing(_ names: [String]) -> [String] {
        names.filter { name in
            guard let url = url(for: name) else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    static func remove(_ name: String) {
        guard let url = url(for: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Copies a chosen photo in, downscaled and re-encoded as JPEG.
    /// Returns the stored file name.
    @discardableResult
    static func addPhoto(from source: URL) -> String? {
        guard let image = NSImage(contentsOf: source),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )

        guard let context = CGContext(
            data: nil,
            width: Int(target.width),
            height: Int(target.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: target))

        guard let scaled = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: scaled)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { return nil }

        let name = UUID().uuidString + ".jpg"
        guard let destination = url(for: name) else { return nil }
        do {
            try data.write(to: destination, options: .atomic)
            return name
        } catch {
            return nil
        }
    }
}

enum SharedStore {
    static let appGroup = "FRWW9Y9Y94.com.widgetmac.desktop"

    /// The widget extension must be sandboxed for WidgetKit to register it at
    /// all, so the App Group container is the only place both processes can
    /// reach. Application Support remains a fallback for the unsandboxed app
    /// when no group is provisioned.
    static var directory: URL {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return group
        }
        let base = SupportDirectory.root
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static var snapshotURL: URL { directory.appendingPathComponent("widget-snapshot.json") }

    static func load() -> WidgetSnapshot {
        guard let data = try? Data(contentsOf: snapshotURL),
              let decoded = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .placeholder }
        return decoded
    }

    /// Returns true when the file actually changed, so the caller can skip a
    /// pointless WidgetKit reload.
    @discardableResult
    static func save(_ snapshot: WidgetSnapshot) -> Bool {
        var next = snapshot
        next.updated = .now
        var previous = load()
        previous.updated = next.updated
        guard previous != next else { return false }
        guard let data = try? JSONEncoder().encode(next) else { return false }
        try? data.write(to: snapshotURL, options: .atomic)
        // This file carries recent clipboard text so the widget can show it,
        // and an atomic write takes the default 0644. The clipboard store
        // itself is encrypted; there is no reason for its most recent entries
        // to be the one copy readable by anything that can reach the path.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: snapshotURL.path)
        return true
    }
}
