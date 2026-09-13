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
    var themeName: String = "Midnight Focus"
    var startHex: UInt32 = 0x1D2B4A
    var endHex: UInt32 = 0x321432
    var accentHex: UInt32 = 0xFF5A1F
    var secondaryHex: UInt32 = 0xE36A96
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

    static func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func image(named name: String) -> NSImage? {
        NSImage(contentsOf: url(for: name))
    }

    /// Drops names whose files are gone, so a deleted photo cannot leave the
    /// widget pointing at nothing.
    static func existing(_ names: [String]) -> [String] {
        names.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
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
        do {
            try data.write(to: url(for: name), options: .atomic)
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
        return true
    }
}
