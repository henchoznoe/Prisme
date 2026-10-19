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
        NSGradient(starting: NSColor(red: 0.08, green: 0.19, blue: 0.22, alpha: 1), ending: NSColor(red: 0.04, green: 0.09, blue: 0.13, alpha: 1))!.draw(in: background, angle: -60)
        let prism = NSBezierPath()
        prism.move(to: NSPoint(x: p * 0.51, y: p * 0.79))
        prism.line(to: NSPoint(x: p * 0.21, y: p * 0.26))
        prism.line(to: NSPoint(x: p * 0.78, y: p * 0.26))
        prism.close()
        NSGradient(starting: NSColor(red: 0.65, green: 0.98, blue: 0.85, alpha: 1), ending: NSColor(red: 0.25, green: 0.66, blue: 0.70, alpha: 1))!.draw(in: prism, angle: -70)
        let facet = NSBezierPath()
        facet.move(to: NSPoint(x: p * 0.51, y: p * 0.79))
        facet.line(to: NSPoint(x: p * 0.49, y: p * 0.26))
        facet.line(to: NSPoint(x: p * 0.78, y: p * 0.26))
        facet.close()
        NSColor(red: 0.17, green: 0.49, blue: 0.57, alpha: 0.65).setFill()
        facet.fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
