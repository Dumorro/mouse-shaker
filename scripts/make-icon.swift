// Draws the app icon and writes an .icns. Usage: swift scripts/make-icon.swift <out.icns>
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "build/AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MouseShaker.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)

    // macOS icon grid: ~80% body with a continuous-corner squircle.
    let inset = s * 0.1
    let body = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(
        starting: NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.98, alpha: 1),
        ending: NSColor(calibratedRed: 0.62, green: 0.30, blue: 0.93, alpha: 1)
    )!.draw(in: shape, angle: -60)

    // Motion arcs behind the mouse.
    NSColor.white.withAlphaComponent(0.35).setStroke()
    for (i, radius) in [0.30, 0.38].enumerated() {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: s * 0.5, y: s * 0.5), radius: s * radius, startAngle: 20, endAngle: 70)
        arc.lineWidth = s * (0.035 - 0.01 * CGFloat(i))
        arc.lineCapStyle = .round
        arc.stroke()
        let mirror = NSBezierPath()
        mirror.appendArc(withCenter: NSPoint(x: s * 0.5, y: s * 0.5), radius: s * radius, startAngle: 200, endAngle: 250)
        mirror.lineWidth = arc.lineWidth
        mirror.lineCapStyle = .round
        mirror.stroke()
    }

    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = symbol.size
        symbol.draw(in: NSRect(x: (s - size.width) / 2, y: (s - size.height) / 2, width: size.width, height: size.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(points * scale).write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
print("Wrote \(output)")
