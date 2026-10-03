// Draws the Liberty Loader app icon (shield on near-black with a hazard band) and
// writes an .iconset plus a 512 px PNG. Run on macOS:
//   swift scripts/make_icon.swift <output-dir>
// then: iconutil -c icns <output-dir>/AppIcon.iconset
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/icon")
let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let yellow = NSColor(srgbRed: 1.0, green: 0.906, blue: 0.122, alpha: 1)
let background = NSColor(srgbRed: 0.05, green: 0.055, blue: 0.063, alpha: 1)

func render(size: Int) -> Data? {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: ~10% margin, rounded square.
    let inset = s * 0.1
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    tilePath.addClip()
    background.setFill()
    tile.fill()

    // Hazard band along the bottom.
    let bandHeight = tile.height * 0.12
    let band = CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: bandHeight)
    NSColor.black.setFill()
    band.fill()
    ctx.saveGState()
    ctx.clip(to: band)
    yellow.setFill()
    let stripe = bandHeight * 0.9
    var x = tile.minX - bandHeight
    while x < tile.maxX {
        let p = NSBezierPath()
        p.move(to: CGPoint(x: x, y: band.minY))
        p.line(to: CGPoint(x: x + stripe, y: band.minY))
        p.line(to: CGPoint(x: x + stripe + bandHeight, y: band.maxY))
        p.line(to: CGPoint(x: x + bandHeight, y: band.maxY))
        p.close()
        p.fill()
        x += stripe * 2
    }
    ctx.restoreGState()

    // Shield.
    let w = tile.width * 0.5
    let h = tile.height * 0.58
    let cx = tile.midX
    let top = tile.maxY - tile.height * 0.14
    let shield = NSBezierPath()
    shield.move(to: CGPoint(x: cx, y: top))
    shield.line(to: CGPoint(x: cx + w / 2, y: top - h * 0.13))
    shield.line(to: CGPoint(x: cx + w / 2, y: top - h * 0.5))
    shield.curve(to: CGPoint(x: cx, y: top - h), controlPoint1: CGPoint(x: cx + w / 2, y: top - h * 0.78), controlPoint2: CGPoint(x: cx + w * 0.22, y: top - h * 0.93))
    shield.curve(to: CGPoint(x: cx - w / 2, y: top - h * 0.5), controlPoint1: CGPoint(x: cx - w * 0.22, y: top - h * 0.93), controlPoint2: CGPoint(x: cx - w / 2, y: top - h * 0.78))
    shield.line(to: CGPoint(x: cx - w / 2, y: top - h * 0.13))
    shield.close()
    yellow.setFill()
    shield.fill()

    // Right half shaded for depth.
    ctx.saveGState()
    shield.addClip()
    NSColor.black.withAlphaComponent(0.22).setFill()
    CGRect(x: cx, y: top - h, width: w, height: h).fill()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(size: px)?.write(to: iconset.appendingPathComponent(name))
    }
}
try render(size: 512)?.write(to: outDir.appendingPathComponent("icon-512.png"))
print("Wrote \(iconset.path)")
