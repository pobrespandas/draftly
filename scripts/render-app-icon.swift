import AppKit

// Render the original Draftly mark at each macOS icon size.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func render(_ size: Int, name: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(size) / 1024)
    transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190)
    NSGradient(starting: NSColor(srgbRed: 0.25, green: 0.38, blue: 0.94, alpha: 1), ending: NSColor(srgbRed: 0.52, green: 0.31, blue: 0.86, alpha: 1))!.draw(in: tile, angle: 55)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 22; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.set()
    NSColor.white.withAlphaComponent(0.28).setFill()
    NSBezierPath(roundedRect: NSRect(x: 345, y: 265, width: 430, height: 550), xRadius: 42, yRadius: 42).fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 249, y: 214, width: 430, height: 550), xRadius: 42, yRadius: 42).fill()
    NSGraphicsContext.restoreGraphicsState()
    let ink = NSColor(srgbRed: 0.29, green: 0.38, blue: 0.83, alpha: 1)
    ink.withAlphaComponent(0.3).setFill()
    for y in [640, 563, 486] {
        NSBezierPath(roundedRect: NSRect(x: 320, y: y, width: y == 486 ? 155 : 280, height: 22), xRadius: 11, yRadius: 11).fill()
    }
    NSGraphicsContext.saveGraphicsState()
    let penTransform = NSAffineTransform(); penTransform.translateX(by: 578, yBy: 324)
    penTransform.rotate(byDegrees: -38); penTransform.concat()
    ink.setFill()
    NSBezierPath(roundedRect: NSRect(x: -42, y: 0, width: 84, height: 336), xRadius: 20, yRadius: 20).fill()
    let tip = NSBezierPath(); tip.move(to: NSPoint(x: -42, y: -8)); tip.line(to: NSPoint(x: 42, y: -8)); tip.line(to: NSPoint(x: 0, y: -82)); tip.close(); tip.fill()
    NSColor.white.withAlphaComponent(0.8).setFill()
    NSBezierPath(rect: NSRect(x: -42, y: 260, width: 84, height: 14)).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
for size in [16, 32, 128, 256, 512] {
    try render(size, name: "icon_\(size)x\(size).png")
    try render(size * 2, name: "icon_\(size)x\(size)@2x.png")
}
