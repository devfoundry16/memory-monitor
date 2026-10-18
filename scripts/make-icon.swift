// Draws the Fresh app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift [preview.png]
import AppKit

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// Apple's icon shape is a superellipse, not a plain rounded rectangle.
func squircle(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let n = 5.0, a = rect.width / 2, b = rect.height / 2
    for step in 0...360 {
        let t = Double(step) * .pi / 180
        let c = cos(t), s = sin(t)
        let x = a * pow(abs(c), 2 / n) * (c < 0 ? -1 : 1)
        let y = b * pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)
        let point = CGPoint(x: rect.midX + x, y: rect.midY + y)
        step == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

/// Draws the icon on a 1024-point grid, scaled to `pixels`.
func render(pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let center = CGPoint(x: 512, y: 512)

    // Body: dark green-black tile with a soft drop shadow, on Apple's 824-point grid.
    let body = squircle(in: CGRect(x: 100, y: 100, width: 824, height: 824))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: color(0x000000, 0.35))
    ctx.addPath(body)
    ctx.setFillColor(color(0x0b0f0d))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let background = CGGradient(colorsSpace: nil, colors: [color(0x22302a), color(0x0a0e0c)] as CFArray,
                                locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // Hairline highlight along the edge.
    ctx.addPath(body)
    ctx.setStrokeColor(color(0xffffff, 0.08))
    ctx.setLineWidth(4)
    ctx.strokePath()

    // Leaf: an almond-shaped blade in Fresh's greens, tilted to the upper right, with a
    // midrib, side veins and a short stem. Drawn upright, then rotated about the centre.
    ctx.saveGState()
    ctx.translateBy(x: center.x + 10, y: center.y - 6)
    ctx.rotate(by: -0.62)

    let blade = CGMutablePath()
    blade.move(to: CGPoint(x: 0, y: -290))
    blade.addCurve(to: CGPoint(x: 0, y: 330), control1: CGPoint(x: 330, y: -130), control2: CGPoint(x: 70, y: 270))
    blade.addCurve(to: CGPoint(x: 0, y: -290), control1: CGPoint(x: -60, y: 270), control2: CGPoint(x: -300, y: -120))
    blade.closeSubpath()

    // Stem first, so the blade covers where they meet.
    let stem = CGMutablePath()
    stem.move(to: CGPoint(x: 0, y: -250))
    stem.addQuadCurve(to: CGPoint(x: -34, y: -410), control: CGPoint(x: 6, y: -350))
    ctx.addPath(stem)
    ctx.setLineCap(.round)
    ctx.setLineWidth(30)
    ctx.setStrokeColor(color(0x2fbf71))
    ctx.strokePath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: color(0x000000, 0.45))
    ctx.addPath(blade)
    ctx.setFillColor(color(0x2fbf71))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(blade)
    ctx.clip()
    let green = CGGradient(colorsSpace: nil, colors: [color(0x22a862), color(0x5fd36f), color(0xc4f25a)] as CFArray,
                           locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(green, start: CGPoint(x: -120, y: -290), end: CGPoint(x: 120, y: 330), options: [])
    // A soft sheen on one half of the blade.
    let sheen = CGMutablePath()
    sheen.move(to: CGPoint(x: 0, y: -290))
    sheen.addCurve(to: CGPoint(x: 0, y: 330), control1: CGPoint(x: 330, y: -130), control2: CGPoint(x: 70, y: 270))
    sheen.addLine(to: CGPoint(x: 0, y: -290))
    ctx.addPath(sheen)
    ctx.setFillColor(color(0xffffff, 0.10))
    ctx.fillPath()

    // Veins: a midrib and four pairs angled toward the tip.
    let vein = color(0x0e3b22, 0.55)
    ctx.setStrokeColor(vein)
    ctx.setLineCap(.round)
    let midrib = CGMutablePath()
    midrib.move(to: CGPoint(x: 0, y: -270))
    midrib.addQuadCurve(to: CGPoint(x: 0, y: 290), control: CGPoint(x: 14, y: 20))
    ctx.addPath(midrib)
    ctx.setLineWidth(16)
    ctx.strokePath()
    ctx.setLineWidth(9)
    for (y, reach) in [(CGFloat(-170), CGFloat(130)), (-60, 135), (50, 115), (150, 78)] {
        for side in [CGFloat(1), -1] {
            let veinPath = CGMutablePath()
            veinPath.move(to: CGPoint(x: side * 4, y: y))
            veinPath.addQuadCurve(to: CGPoint(x: side * reach, y: y + 95),
                                  control: CGPoint(x: side * reach * 0.45, y: y + 20))
            ctx.addPath(veinPath)
            ctx.strokePath()
        }
    }
    ctx.restoreGState()
    ctx.restoreGState()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try data.write(to: url)
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try writePNG(render(pixels: size), to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try writePNG(render(pixels: size * 2), to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
if CommandLine.arguments.count > 1 {
    try writePNG(render(pixels: 1024), to: URL(fileURLWithPath: CommandLine.arguments[1]))
}

let output = repo.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(output.path)")
