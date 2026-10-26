import AppKit
import Foundation

// Uses system SVG rendering. No copied SVG data or generated images enter source.
let arguments = CommandLine.arguments
if arguments.count != 3 { fatalError("Usage: render_icons.swift SOURCE.svg OUTPUT.iconset") }
guard let image = NSImage(contentsOfFile: arguments[1]) else { fatalError("Cannot open icon SVG") }
let directory = URL(fileURLWithPath: arguments[2])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for logical in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = logical * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError("Icon allocation failed") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon encoding failed") }
        try png.write(to: directory.appendingPathComponent("icon_\(logical)x\(logical)\(suffix).png"))
    }
}
