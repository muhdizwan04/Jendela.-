import AppKit
import CoreGraphics
import Foundation

// Draws the app icon and emits a full .iconset.
//
// "Jendela" is Malay for window, so the mark is a window: a four-pane aperture
// in a dark warm plate, with light coming through it. A notch shape was the
// obvious motif and the wrong one — it is the same mark every notch utility
// uses. Deliberately few shapes: anything finer turns to mush at 16pt, which
// is where an app icon is actually seen.

let canvas: CGFloat = 1024
// macOS icons sit inside their canvas rather than filling it.
let inset: CGFloat = 100
let plate = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let plateRadius = plate.width * 0.2237   // Apple's squircle ratio

func colour(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func render() -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: Int(canvas), height: Int(canvas),
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let plateShape = CGPath(roundedRect: plate, cornerWidth: plateRadius, cornerHeight: plateRadius, transform: nil)

    // Soft drop shadow, so the plate sits on light and dark docks alike.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 46, color: colour(0x000000, 0.45))
    ctx.addPath(plateShape)
    ctx.setFillColor(colour(0x151110))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(plateShape)
    ctx.clip()

    // Warm near-black body. Dark enough that the lit panes carry the whole
    // icon, warm enough that it never reads as plain graphite.
    let body = CGGradient(
        colorsSpace: space,
        colors: [colour(0x2A211C), colour(0x191311), colour(0x0E0A09)] as CFArray,
        locations: [0, 0.55, 1]
    )!
    ctx.drawLinearGradient(
        body,
        start: CGPoint(x: plate.minX, y: plate.maxY),
        end: CGPoint(x: plate.maxX, y: plate.minY),
        options: []
    )

    // The window aperture. Drawn as one rounded opening and then split by
    // straight mullion bars — four separately rounded panes left a dark blob
    // where their corners met, which at 16pt looked like a smudge.
    let frame = CGRect(x: plate.midX - 236, y: plate.midY - 250, width: 472, height: 500)
    let aperture = CGPath(roundedRect: frame, cornerWidth: 74, cornerHeight: 74, transform: nil)

    ctx.saveGState()
    ctx.addPath(aperture)
    ctx.clip()

    // Light through the glass: one source at the top left, falling off across
    // the diagonal.
    let glass = CGGradient(
        colorsSpace: space,
        colors: [colour(0xFFD3A3), colour(0xFF8A3D), colour(0xFF5A1F), colour(0xD23F11)] as CFArray,
        locations: [0, 0.34, 0.70, 1]
    )!
    ctx.drawLinearGradient(
        glass,
        start: CGPoint(x: frame.minX, y: frame.maxY),
        end: CGPoint(x: frame.maxX, y: frame.minY),
        options: []
    )
    ctx.restoreGState()

    // Mullions: the body colour cut back through the opening.
    let mullion: CGFloat = 38
    ctx.setFillColor(colour(0x171211))
    ctx.fill(CGRect(x: frame.midX - mullion / 2, y: frame.minY, width: mullion, height: frame.height))
    ctx.fill(CGRect(x: frame.minX, y: frame.midY - mullion / 2, width: frame.width, height: mullion))

    // A hairline along the top, the way glass catches light.
    ctx.setStrokeColor(colour(0xFFFFFF, 0.14))
    ctx.setLineWidth(3)
    ctx.addPath(plateShape)
    ctx.strokePath()

    ctx.restoreGState()
    return ctx.makeImage()!
}

let master = render()
let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for entry in sizes {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: entry.px, height: entry.px,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.draw(master, in: CGRect(x: 0, y: 0, width: entry.px, height: entry.px))
    let image = ctx.makeImage()!
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try data.write(to: out.appendingPathComponent("\(entry.name).png"))
}
print("wrote \(sizes.count) sizes to \(out.path)")
