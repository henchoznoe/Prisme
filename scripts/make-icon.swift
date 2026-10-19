import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let background = NSBezierPath(roundedRect: NSRect(x: p * 0.04, y: p * 0.04, width: p * 0.92, height: p * 0.92), xRadius: p * 0.21, yRadius: p * 0.21)
        NSGradient(starting: NSColor(red: 0.40, green: 0.70, blue: 1, alpha: 1), ending: NSColor(red: 0.05, green: 0.21, blue: 0.70, alpha: 1))!.draw(in: background, angle: -60)
        let prism = NSBezierPath()
        prism.move(to: NSPoint(x: p * 0.51, y: p * 0.79))
        prism.line(to: NSPoint(x: p * 0.21, y: p * 0.26))
        prism.line(to: NSPoint(x: p * 0.78, y: p * 0.26))
        prism.close()
        NSGradient(starting: NSColor(red: 0.96, green: 0.99, blue: 1, alpha: 1), ending: NSColor(red: 0.50, green: 0.78, blue: 1, alpha: 1))!.draw(in: prism, angle: -70)
        let facet = NSBezierPath()
        facet.move(to: NSPoint(x: p * 0.51, y: p * 0.79))
        facet.line(to: NSPoint(x: p * 0.49, y: p * 0.26))
        facet.line(to: NSPoint(x: p * 0.78, y: p * 0.26))
        facet.close()
        NSColor(red: 0.12, green: 0.37, blue: 0.89, alpha: 0.65).setFill()
        facet.fill()
        let rim = NSBezierPath(roundedRect: NSRect(x: p * 0.055, y: p * 0.055, width: p * 0.89, height: p * 0.89), xRadius: p * 0.20, yRadius: p * 0.20)
        NSColor.white.withAlphaComponent(0.40).setStroke()
        rim.lineWidth = max(1, p * 0.009)
        rim.stroke()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
