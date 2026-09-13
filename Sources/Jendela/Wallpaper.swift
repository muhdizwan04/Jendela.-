import AppKit
import Foundation

/// Renders desktop pictures: theme gradients, and a TopNotch-style mask that
/// blacks out the menu-bar strip so the notch blends into the screen.
///
/// All of this is a one-shot cost. The image is drawn once, cached on disk and
/// handed to the window server; nothing stays resident, so a themed or
/// notch-masked desktop costs exactly zero CPU afterwards.
enum WallpaperRenderer {
    enum Failure: Error { case renderFailed, noSource }

    /// What to draw for one screen.
    struct Job: Sendable {
        var index: Int
        var pixelSize: CGSize
        /// Height of the black bar in pixels; 0 leaves the image untouched.
        var maskHeight: CGFloat
        var source: Source

        enum Source: Sendable {
            case gradient(id: String, start: RGB, end: RGB, accent: RGB)
            case image(path: String)
        }
    }

    struct RGB: Sendable { var r, g, b: Double }

    private static var cacheDirectory: URL {
        let base = SupportDirectory.root
            .appendingPathComponent("Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// True when `url` is one of ours, so we never treat a generated picture as
    /// the user's original and mask it twice.
    static func isGenerated(_ url: URL) -> Bool {
        url.path.hasPrefix(cacheDirectory.path)
    }

    @MainActor
    static func currentWallpapers() -> [Int: URL] {
        var out: [Int: URL] = [:]
        for (index, screen) in NSScreen.screens.enumerated() {
            if let url = NSWorkspace.shared.desktopImageURL(for: screen) { out[index] = url }
        }
        return out
    }

    @MainActor
    static func run(_ jobs: [Job], completion: @escaping @MainActor (Error?) -> Void) {
        guard !jobs.isEmpty else { completion(nil); return }
        DispatchQueue.global(qos: .userInitiated).async {
            var urls: [Int: URL] = [:]
            var failure: Error?
            for job in jobs {
                do { urls[job.index] = try render(job) } catch { failure = error }
            }
            let resolved = urls
            let outcome = failure
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    set(resolved)
                    completion(outcome)
                }
            }
        }
    }

    @MainActor
    static func set(_ urls: [Int: URL]) {
        for (index, screen) in NSScreen.screens.enumerated() {
            guard let url = urls[index] else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    // MARK: - Drawing

    private static func render(_ job: Job) throws -> URL {
        let name: String
        switch job.source {
        case .gradient(let id, _, _, _):
            name = "theme-\(id)-\(Int(job.pixelSize.width))x\(Int(job.pixelSize.height))-m\(Int(job.maskHeight)).png"
        case .image(let path):
            let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let digest = abs(path.hashValue)
            name = "masked-\(stem)-\(digest)-\(Int(job.pixelSize.width))x\(Int(job.pixelSize.height))-m\(Int(job.maskHeight)).png"
        }
        let url = cacheDirectory.appendingPathComponent(name)

        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil,
            width: Int(job.pixelSize.width),
            height: Int(job.pixelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw Failure.renderFailed }

        switch job.source {
        case .gradient(_, let start, let end, let accent):
            try drawGradient(context, size: job.pixelSize, space: space, start: start, end: end, accent: accent)
        case .image(let path):
            try drawImage(context, size: job.pixelSize, path: path)
        }

        if job.maskHeight > 0 {
            // The notch itself is pure black, so a black strip across the menu
            // bar makes the cut-out disappear into it.
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(
                x: 0,
                y: job.pixelSize.height - job.maskHeight,
                width: job.pixelSize.width,
                height: job.maskHeight
            ))
        }

        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw Failure.renderFailed }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func drawGradient(
        _ context: CGContext, size: CGSize, space: CGColorSpace,
        start: RGB, end: RGB, accent: RGB
    ) throws {
        let from = CGColor(red: start.r, green: start.g, blue: start.b, alpha: 1)
        let to = CGColor(red: end.r, green: end.g, blue: end.b, alpha: 1)
        guard let gradient = CGGradient(colorsSpace: space, colors: [from, to] as CFArray, locations: [0, 1])
        else { throw Failure.renderFailed }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: size.height),
            end: CGPoint(x: size.width, y: 0),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        let bloom = CGColor(red: accent.r, green: accent.g, blue: accent.b, alpha: 0.22)
        let clear = CGColor(red: accent.r, green: accent.g, blue: accent.b, alpha: 0)
        if let radial = CGGradient(colorsSpace: space, colors: [bloom, clear] as CFArray, locations: [0, 1]) {
            let centre = CGPoint(x: size.width * 0.72, y: size.height * 0.68)
            context.drawRadialGradient(
                radial,
                startCenter: centre, startRadius: 0,
                endCenter: centre, endRadius: size.width * 0.45,
                options: []
            )
        }
    }

    /// Aspect-fills the source into the screen, centred — the same way macOS
    /// itself fits a desktop picture, so masking doesn't reframe the image.
    private static func drawImage(_ context: CGContext, size: CGSize, path: String) throws {
        guard let source = NSImage(contentsOfFile: path),
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { throw Failure.noSource }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let scale = max(size.width / imageSize.width, size.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(
            x: (size.width - drawn.width) / 2,
            y: (size.height - drawn.height) / 2,
            width: drawn.width,
            height: drawn.height
        ))
    }
}
