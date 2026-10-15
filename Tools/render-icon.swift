import AppKit

let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let bg = NSColor(red: 0.025, green: 0.055, blue: 0.08, alpha: 1)
let copper = NSColor(red: 1, green: 0.64, blue: 0.34, alpha: 1)
let cyan = NSColor(red: 0.30, green: 0.87, blue: 0.93, alpha: 1)
bg.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
NSColor(white: 1, alpha: 0.055).setStroke()
for n in stride(from: 64, through: 1024, by: 64) {
    let grid = NSBezierPath(); grid.lineWidth = 1
    grid.move(to: NSPoint(x: n, y: 0)); grid.line(to: NSPoint(x: n, y: 1024))
    grid.move(to: NSPoint(x: 0, y: n)); grid.line(to: NSPoint(x: 1024, y: n)); grid.stroke()
}
func gear(_ cx: Double, _ cy: Double, _ radius: Double, _ teeth: Int, _ color: NSColor, _ rotation: Double) {
    let path = NSBezierPath()
    for i in 0..<(teeth * 4) {
        let angle = Double(i) / Double(teeth * 4) * .pi * 2 + rotation
        let r = radius * ([0, 3].contains(i % 4) ? 0.88 : 1)
        let point = NSPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r)
        if i == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    path.close(); color.setFill(); path.fill()
    bg.setFill(); NSBezierPath(ovalIn: NSRect(x: cx - radius * 0.68, y: cy - radius * 0.68, width: radius * 1.36, height: radius * 1.36)).fill()
    color.setFill()
    for i in 0..<5 {
        let angle = Double(i) / 5 * .pi * 2 + rotation
        let spoke = NSBezierPath(); spoke.lineWidth = radius * 0.14; spoke.lineCapStyle = .round
        spoke.move(to: NSPoint(x: cx, y: cy)); spoke.line(to: NSPoint(x: cx + cos(angle) * radius * 0.65, y: cy + sin(angle) * radius * 0.65))
        color.setStroke(); spoke.stroke()
    }
    color.setFill(); NSBezierPath(ovalIn: NSRect(x: cx - radius * 0.21, y: cy - radius * 0.21, width: radius * 0.42, height: radius * 0.42)).fill()
    bg.setFill(); NSBezierPath(ovalIn: NSRect(x: cx - radius * 0.08, y: cy - radius * 0.08, width: radius * 0.16, height: radius * 0.16)).fill()
}
gear(411, 570, 279, 16, copper, 0.10)
gear(732, 328, 147, 10, cyan, 0.31)
let orbit = NSBezierPath(ovalIn: NSRect(x: 118, y: 275, width: 584, height: 584))
orbit.lineWidth = 3; NSColor(red: 1, green: 0.64, blue: 0.34, alpha: 0.25).setStroke(); orbit.stroke()
image.unlockFocus()
// App icons must carry opaque RGB pixels, even when the artwork already fills
// every pixel. Flatten into a context with no alpha channel before PNG export.
let source = NSBitmapImageRep(data: image.tiffRepresentation!)!.cgImage!
let opaque = CGContext(data: nil, width: source.width, height: source.height,
                       bitsPerComponent: 8, bytesPerRow: source.width * 4,
                       space: source.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
opaque.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
let data = NSBitmapImageRep(cgImage: opaque.makeImage()!).representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
