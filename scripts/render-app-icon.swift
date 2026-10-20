import AppKit

// Render the original Draftly mark at each macOS icon size.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func drawMark(monochrome: Bool) {
    NSGraphicsContext.saveGraphicsState()
    if !monochrome {
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = 22; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.set()
    }
    let back = NSBezierPath(roundedRect: NSRect(x: 345, y: 265, width: 430, height: 550), xRadius: 42, yRadius: 42)
    let front = NSBezierPath(roundedRect: NSRect(x: 249, y: 214, width: 430, height: 550), xRadius: 42, yRadius: 42)
    if monochrome {
        NSColor.black.setStroke()
        let backEdge = NSBezierPath()
        backEdge.move(to: NSPoint(x: 345, y: 790))
        backEdge.line(to: NSPoint(x: 345, y: 815))
        backEdge.line(to: NSPoint(x: 735, y: 815))
        backEdge.curve(to: NSPoint(x: 775, y: 775), controlPoint1: NSPoint(x: 765, y: 815), controlPoint2: NSPoint(x: 775, y: 805))
        backEdge.line(to: NSPoint(x: 775, y: 520))
        backEdge.lineWidth = 32; backEdge.lineCapStyle = .round; backEdge.stroke()
        front.lineWidth = 32; front.stroke()
    } else {
        NSColor.white.withAlphaComponent(0.38).setFill(); back.fill()
        NSColor.white.setFill(); front.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    let ink = monochrome ? NSColor.black : NSColor(srgbRed: 0.29, green: 0.38, blue: 0.83, alpha: 1)
    ink.withAlphaComponent(monochrome ? 1 : 0.3).setFill()
    for y in [640, 563, 486] {
        NSBezierPath(roundedRect: NSRect(x: 320, y: y, width: y == 486 ? 155 : 280, height: monochrome ? 30 : 22), xRadius: 11, yRadius: 11).fill()
    }
    NSGraphicsContext.saveGraphicsState()
    let penTransform = NSAffineTransform(); penTransform.translateX(by: 578, yBy: 324)
    penTransform.rotate(byDegrees: -38); penTransform.concat()
    ink.setFill()
    NSBezierPath(roundedRect: NSRect(x: -42, y: 0, width: 84, height: 336), xRadius: 20, yRadius: 20).fill()
    let tip = NSBezierPath(); tip.move(to: NSPoint(x: -42, y: -8)); tip.line(to: NSPoint(x: 42, y: -8)); tip.line(to: NSPoint(x: 0, y: -82)); tip.close(); tip.fill()
    if !monochrome {
        NSColor.white.withAlphaComponent(0.8).setFill()
        NSBezierPath(rect: NSRect(x: -42, y: 260, width: 84, height: 14)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
}
func render(_ size: Int, name: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(size) / 1024)
    transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190)
    NSGradient(starting: NSColor(srgbRed: 0.25, green: 0.38, blue: 0.94, alpha: 1), ending: NSColor(srgbRed: 0.52, green: 0.31, blue: 0.86, alpha: 1))!.draw(in: tile, angle: 55)
    drawMark(monochrome: false)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
for size in [16, 32, 128, 256, 512] {
    try render(size, name: "icon_\(size)x\(size).png")
    try render(size * 2, name: "icon_\(size)x\(size)@2x.png")
}

// Use the same geometry for the template image in the menu bar.
final class MenuMarkView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let transform = NSAffineTransform()
        transform.translateX(by: -2, yBy: -2)
        transform.scale(by: 22 / 1024)
        transform.concat()
        drawMark(monochrome: true)
    }
}
let menuMark = MenuMarkView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
try menuMark.dataWithPDF(inside: menuMark.bounds).write(to: output.appendingPathComponent("DraftlyMenuMark.pdf"))
