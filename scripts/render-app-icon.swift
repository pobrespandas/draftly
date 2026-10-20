import AppKit

// Render the original Draftly mark at each macOS icon size.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
// Both assets use this path. Only the ink color changes.
func drawMark(monochrome: Bool) {
    (monochrome ? NSColor.black : NSColor.white).setStroke()
    let sheet = NSBezierPath()
    sheet.move(to: NSPoint(x: 628, y: 768))
    sheet.line(to: NSPoint(x: 320, y: 768))
    sheet.curve(to: NSPoint(x: 272, y: 720), controlPoint1: NSPoint(x: 293, y: 768), controlPoint2: NSPoint(x: 272, y: 747))
    sheet.line(to: NSPoint(x: 272, y: 288))
    sheet.curve(to: NSPoint(x: 320, y: 240), controlPoint1: NSPoint(x: 272, y: 261), controlPoint2: NSPoint(x: 293, y: 240))
    sheet.line(to: NSPoint(x: 656, y: 240))
    sheet.curve(to: NSPoint(x: 704, y: 288), controlPoint1: NSPoint(x: 683, y: 240), controlPoint2: NSPoint(x: 704, y: 261))
    sheet.line(to: NSPoint(x: 704, y: 692))
    sheet.line(to: NSPoint(x: 628, y: 768))
    sheet.line(to: NSPoint(x: 628, y: 692))
    sheet.line(to: NSPoint(x: 704, y: 692))
    sheet.lineWidth = 44
    sheet.lineJoinStyle = .round
    sheet.lineCapStyle = .round
    sheet.stroke()

    let back = NSBezierPath()
    back.move(to: NSPoint(x: 368, y: 848))
    back.line(to: NSPoint(x: 704, y: 848))
    back.curve(to: NSPoint(x: 784, y: 768), controlPoint1: NSPoint(x: 748, y: 848), controlPoint2: NSPoint(x: 784, y: 812))
    back.line(to: NSPoint(x: 784, y: 352))
    back.lineWidth = 44
    back.lineCapStyle = .round
    back.stroke()

    let lines = NSBezierPath()
    for (y, end) in [(564, 592), (444, 532)] {
        lines.move(to: NSPoint(x: 384, y: y))
        lines.line(to: NSPoint(x: end, y: y))
    }
    lines.lineWidth = 44
    lines.lineCapStyle = .round
    lines.stroke()
}
func render(_ size: Int, name: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(size) / 1024)
    transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 190, yRadius: 190)
    NSGradient(starting: NSColor(srgbRed: 0.25, green: 0.38, blue: 0.94, alpha: 1), ending: NSColor(srgbRed: 0.52, green: 0.31, blue: 0.86, alpha: 1))!.draw(in: tile, angle: 55)
    let markTransform = NSAffineTransform()
    markTransform.translateX(by: -16, yBy: -32)
    markTransform.concat()
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
        transform.translateX(by: -5.4375, yBy: -5.875)
        transform.scale(by: 28 / 1024)
        transform.concat()
        drawMark(monochrome: true)
    }
}
let menuMark = MenuMarkView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
try menuMark.dataWithPDF(inside: menuMark.bounds).write(to: output.appendingPathComponent("DraftlyMenuMark.pdf"))
