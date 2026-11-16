// Draws Paster's original app icon (stacked clip cards on a gradient squircle) at 1024 px.
// Usage: swift scripts/make_icon.swift out.png
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824 px squircle centred in 1024 px canvas.
let inset: CGFloat = 100
let body = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.current?.saveGraphicsState()
shadow.set()
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.45, blue: 0.30, alpha: 1),
                    NSColor(srgbRed: 0.93, green: 0.22, blue: 0.47, alpha: 1),
                    NSColor(srgbRed: 0.45, green: 0.25, blue: 0.85, alpha: 1)])!
    .draw(in: squircle, angle: -60)
NSGraphicsContext.current?.restoreGraphicsState()

// Three fanned cards, each with a coloured header strip like the app's own cards.
func card(center: NSPoint, angle: CGFloat, header: NSColor, alpha: CGFloat) {
    let w: CGFloat = 420, h: CGFloat = 470
    let t = NSAffineTransform()
    t.translateX(by: center.x, yBy: center.y)
    t.rotate(byDegrees: angle)
    NSGraphicsContext.current?.saveGraphicsState()
    t.concat()
    let r = NSRect(x: -w / 2, y: -h / 2, width: w, height: h)
    let s = NSShadow()
    s.shadowColor = NSColor.black.withAlphaComponent(0.28)
    s.shadowBlurRadius = 24
    s.shadowOffset = NSSize(width: 0, height: -10)
    NSGraphicsContext.current?.saveGraphicsState()
    s.set()
    let p = NSBezierPath(roundedRect: r, xRadius: 44, yRadius: 44)
    NSColor.white.withAlphaComponent(alpha).setFill()
    p.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    p.addClip()
    header.setFill()
    NSRect(x: r.minX, y: r.maxY - 112, width: w, height: 112).fill()
    NSColor(white: 0.80, alpha: 1).setFill()
    for (i, frac) in [0.78, 0.62, 0.70, 0.45].enumerated() {
        let y = r.maxY - 170 - CGFloat(i) * 62
        NSBezierPath(roundedRect: NSRect(x: r.minX + 46, y: y, width: (w - 92) * frac, height: 26),
                     xRadius: 13, yRadius: 13).fill()
    }
    NSGraphicsContext.current?.restoreGraphicsState()
}
card(center: NSPoint(x: 430, y: 520), angle: 14, header: NSColor(srgbRed: 0.20, green: 0.70, blue: 0.75, alpha: 1), alpha: 0.85)
card(center: NSPoint(x: 512, y: 500), angle: 4, header: NSColor(srgbRed: 0.98, green: 0.72, blue: 0.20, alpha: 1), alpha: 0.93)
card(center: NSPoint(x: 590, y: 480), angle: -8, header: NSColor(srgbRed: 0.24, green: 0.48, blue: 0.96, alpha: 1), alpha: 1)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
