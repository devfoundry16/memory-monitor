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

    // Gauge: a 270° track with a fresh-green reading most of the way round.
    let radius: CGFloat = 268, width: CGFloat = 78
    let start = CGFloat.pi * 1.25, end = -CGFloat.pi * 0.25
    ctx.setLineCap(.round)
    ctx.setLineWidth(width)
    ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    ctx.setStrokeColor(color(0xffffff, 0.09))
    ctx.strokePath()

    let reading = start - (start - end) * 0.72
    ctx.saveGState()
    ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: reading, clockwise: true)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let green = CGGradient(colorsSpace: nil, colors: [color(0x2fbf71), color(0xb6f04a)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(green, start: CGPoint(x: 230, y: 250), end: CGPoint(x: 700, y: 820), options: [])
    ctx.restoreGState()

    // Memory, CPU and GPU as three bars inside the gauge.
    let barWidth: CGFloat = 60, gap: CGFloat = 34, floor: CGFloat = 392
    let heights: [CGFloat] = [150, 236, 190]
    let left = center.x - (barWidth * 3 + gap * 2) / 2
    for (index, height) in heights.enumerated() {
        let rect = CGRect(x: left + CGFloat(index) * (barWidth + gap), y: floor, width: barWidth, height: height)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        ctx.setFillColor(color(0xffffff, index == 1 ? 1 : 0.82))
        ctx.fillPath()
    }
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
