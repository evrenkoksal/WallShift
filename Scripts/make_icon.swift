// Renders the app icon from an SF Symbol so the bundle has a real .icns.
import AppKit

let size = CGFloat(1024)
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.29, green: 0.44, blue: 0.94, alpha: 1),
    NSColor(calibratedRed: 0.55, green: 0.28, blue: 0.85, alpha: 1),
])!
gradient.draw(in: path, angle: 290)

let config = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .medium)
if let symbol = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    NSColor.white.set()
    NSRect(origin: .zero, size: symbol.size).fill()
    symbol.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
    tinted.unlockFocus()
    let origin = NSPoint(x: (size - tinted.size.width) / 2, y: (size - tinted.size.height) / 2)
    tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
}

image.unlockFocus()

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
if let tiff = image.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try png.write(to: URL(fileURLWithPath: output))
}
