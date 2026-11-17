// Draws the app icon and writes Resources/AppIcon.icns.
//   swift scripts/make-icon.swift      (needs iconutil, which ships with macOS)
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    // macOS icon grid: 824 pt rounded square centred in 1024, with a soft drop shadow.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    // Storm sky: slate blue on top, darker below.
    NSGradient(starting: NSColor(red: 0.36, green: 0.47, blue: 0.66, alpha: 1),
               ending: NSColor(red: 0.13, green: 0.17, blue: 0.29, alpha: 1))!.draw(in: shape, angle: -90)
    // The same symbol family as the menu bar icon: white cloud and bolt (one layer), light blue rain.
    let config = NSImage.SymbolConfiguration(pointSize: 470 * s, weight: .medium)
        .applying(.init(paletteColors: [.white, NSColor(red: 0.62, green: 0.82, blue: 1, alpha: 1)]))
    let symbol = NSImage(systemSymbolName: "cloud.bolt.rain.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let size = symbol.size
    symbol.draw(in: NSRect(x: (CGFloat(px) - size.width) / 2, y: (CGFloat(px) - size.height) / 2 - 10 * s,
                           width: size.width, height: size.height))
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    try! render(pt).write(to: iconset.appending(path: "icon_\(pt)x\(pt).png"))
    try! render(pt * 2).write(to: iconset.appending(path: "icon_\(pt)x\(pt)@2x.png"))
}
let out = root.appending(path: "Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! p.run()
p.waitUntilExit()
precondition(p.terminationStatus == 0, "iconutil failed")
try! render(1024).write(to: root.appending(path: "build/icon-preview.png"))
print("Wrote \(out.path)")
