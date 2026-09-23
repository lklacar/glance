import AppKit
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let base = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 205, yRadius: 205)
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.3); shadow.shadowBlurRadius = 25; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.set()
        NSGradient(starting: NSColor(calibratedRed: 0.21, green: 0.37, blue: 0.43, alpha: 1), ending: NSColor(calibratedRed: 0.08, green: 0.17, blue: 0.22, alpha: 1))!.draw(in: base, angle: -90)
        NSShadow().set()
        let photo = NSBezierPath(roundedRect: NSRect(x: 204, y: 258, width: 616, height: 514), xRadius: 64, yRadius: 64)
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill(); photo.fill()
        context.saveGState(); photo.addClip()
        NSColor(calibratedRed: 0.55, green: 0.75, blue: 0.66, alpha: 1).setFill()
        let back = NSBezierPath(); back.move(to: NSPoint(x: 160, y: 258)); back.line(to: NSPoint(x: 390, y: 597)); back.line(to: NSPoint(x: 690, y: 258)); back.close(); back.fill()
        NSColor(calibratedRed: 0.20, green: 0.46, blue: 0.43, alpha: 1).setFill()
        let front = NSBezierPath(); front.move(to: NSPoint(x: 360, y: 250)); front.line(to: NSPoint(x: 663, y: 627)); front.line(to: NSPoint(x: 870, y: 340)); front.line(to: NSPoint(x: 870, y: 250)); front.close(); front.fill()
        NSColor(calibratedRed: 0.93, green: 0.64, blue: 0.32, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 300, y: 631, width: 76, height: 76)).fill()
        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent(filename))
    }
}
