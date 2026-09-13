import AppKit
import CoreGraphics
import Foundation

// Draws the app icon and emits a full .iconset.
//
// The mark is the product: a squircle with the notch cut flush into its top
// edge, and the hub's glow spilling out beneath it. Deliberately only two
// shapes — anything finer turns to mush at 16pt, which is where an app icon is
// seen most often.

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
    ctx.setFillColor(colour(0x1A1430))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(plateShape)
    ctx.clip()

    // Violet body with real depth, bright enough that black reads against it
    // at 16pt and dark enough that the glow has somewhere to fall off to.
    let body = CGGradient(
        colorsSpace: space,
        colors: [colour(0xB794FF), colour(0x7C3AED), colour(0x3B1E7A), colour(0x1E1038)] as CFArray,
        locations: [0, 0.38, 0.78, 1]
    )!
    ctx.drawLinearGradient(
        body,
        start: CGPoint(x: plate.minX, y: plate.maxY),
        end: CGPoint(x: plate.maxX, y: plate.minY),
        options: []
    )

    // The hub itself: the notch, expanded. Flush with the top edge, rounded
    // only at the bottom — the same shape the panel makes on screen.
    let notchWidth: CGFloat = 430
    let notchHeight: CGFloat = 322
    let notchRadius: CGFloat = 96
    let notch = CGRect(
        x: plate.midX - notchWidth / 2,
        y: plate.maxY - notchHeight,
        width: notchWidth,
        height: notchHeight
    )
    let notchPath = CGMutablePath()
    notchPath.move(to: CGPoint(x: notch.minX, y: notch.maxY))
    notchPath.addLine(to: CGPoint(x: notch.minX, y: notch.minY + notchRadius))
    notchPath.addQuadCurve(
        to: CGPoint(x: notch.minX + notchRadius, y: notch.minY),
        control: CGPoint(x: notch.minX, y: notch.minY)
    )
    notchPath.addLine(to: CGPoint(x: notch.maxX - notchRadius, y: notch.minY))
    notchPath.addQuadCurve(
        to: CGPoint(x: notch.maxX, y: notch.minY + notchRadius),
        control: CGPoint(x: notch.maxX, y: notch.minY)
    )
    notchPath.addLine(to: CGPoint(x: notch.maxX, y: notch.maxY))
    notchPath.closeSubpath()

    // Light spilling out from under the hub, as though it has just opened.
    let glow = CGGradient(
        colorsSpace: space,
        colors: [colour(0xFFFFFF, 0.62), colour(0xD8B4FE, 0.34), colour(0xA855F7, 0.10), colour(0xFFFFFF, 0)] as CFArray,
        locations: [0, 0.30, 0.62, 1]
    )!
    // Squashed into an ellipse so it reads as light cast downward from the
    // opening rather than a round blob sitting behind it.
    let centre = CGPoint(x: plate.midX, y: notch.minY - 10)
    ctx.saveGState()
    ctx.translateBy(x: centre.x, y: centre.y)
    ctx.scaleBy(x: 1.75, y: 0.85)
    ctx.translateBy(x: -centre.x, y: -centre.y)
    ctx.drawRadialGradient(glow, startCenter: centre, startRadius: 14,
                           endCenter: centre, endRadius: 250, options: [])
    ctx.restoreGState()

    ctx.addPath(notchPath)
    ctx.setFillColor(colour(0x000000))
    ctx.fillPath()

    // One accent tile inside the hub — the app's own mark, and at 16pt it
    // survives as a single dot of colour that keeps the icon from reading
    // as a plain black slab.
    let tile = CGRect(x: plate.midX - 76, y: notch.minY + 74, width: 152, height: 152)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 48, cornerHeight: 48, transform: nil)
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let tileFill = CGGradient(
        colorsSpace: space,
        colors: [colour(0xF0ABFC), colour(0x8B5CF6)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        tileFill,
        start: CGPoint(x: tile.minX, y: tile.maxY),
        end: CGPoint(x: tile.maxX, y: tile.minY),
        options: []
    )
    ctx.restoreGState()

    // A hairline along the top, the way glass catches light.
    ctx.setStrokeColor(colour(0xFFFFFF, 0.22))
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
