import AppKit

/// Menu bar image: the SF Symbol in the menu bar's text colour plus a coloured level dot (bottom-right).
/// `dotVisible: false` keeps the same size so blinking doesn't shift neighbouring icons.
public func menuBarImage(symbol: String, level: String?, dotVisible: Bool = true) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    let base = (NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        ?? NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)!)
        .withSymbolConfiguration(config)!
    let description = level.map { "Alerta \($0) del SMN" } ?? "Sin alertas del SMN"
    guard let level else {
        base.isTemplate = true            // plain icon: let macOS colour it like every other menu extra
        base.accessibilityDescription = description
        return base
    }

    let dot: CGFloat = 7
    let size = NSSize(width: base.size.width + 3, height: max(base.size.height, 16))
    let color: NSColor = level == "rojo" ? .systemRed : level == "naranja" ? .systemOrange : .systemYellow
    let image = NSImage(size: size, flipped: false) { rect in
        // Glyph tinted with labelColor, resolved against the menu bar's appearance at draw time.
        let glyphRect = NSRect(x: 0, y: (rect.height - base.size.height) / 2, width: base.size.width, height: base.size.height)
        base.draw(in: glyphRect)
        NSColor.labelColor.set()
        glyphRect.fill(using: .sourceAtop)
        guard dotVisible else { return true }
        let dotRect = NSRect(x: rect.maxX - dot, y: 0, width: dot, height: dot)
        NSGraphicsContext.current?.compositingOperation = .clear      // transparent ring around the dot
        NSBezierPath(ovalIn: dotRect.insetBy(dx: -1.5, dy: -1.5)).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        color.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        return true
    }
    image.isTemplate = false
    image.accessibilityDescription = description
    return image
}
