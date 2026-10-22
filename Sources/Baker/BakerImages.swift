import AppKit

/// Authoring sources stay under others/assests; packaging copies their rendered resources.
@MainActor
enum BakerImages {
    private static var templates: [String: NSImage] = [:]
    static func appIcon(dark: Bool) -> NSImage? {
        guard let url = Bundle.main.url(forResource: dark ? "baker_logo_dark" : "baker_logo_light",
                                        withExtension: "svg", subdirectory: "BakerIcons") else { return nil }
        return NSImage(contentsOf: url)
    }

    static func template(_ name: String, folder: String = "BakerSymbols", fallback: String, size: CGFloat = 18) -> NSImage? {
        let key = "\(folder)/\(name)/\(size)"
        if let cached = templates[key] { return cached }
        let custom = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: folder).flatMap(NSImage.init(contentsOf:))
        guard let source = custom ?? symbol(fallback), let image = menuImage(source, size: size) else { return nil }
        templates[key] = image
        return image
    }

    static func system(_ name: String, size: CGFloat = 18) -> NSImage? {
        let key = "system/\(name)/\(size)"
        if let cached = templates[key] { return cached }
        guard let source = symbol(name), let image = menuImage(source, size: size) else { return nil }
        templates[key] = image
        return image
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
    }

    /// Fit visible artwork to a common inset, preserving its aspect ratio.
    /// Rasterisation and alpha inspection happen once per cached icon, never per menu opening.
    private static func menuImage(_ source: NSImage, size: CGFloat) -> NSImage? {
        guard size > 2, source.size.width > 0, source.size.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 96,
                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: 96, height: 96).fill(using: .copy)
        let scale = 96 / max(source.size.width, source.size.height)
        let extent = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        source.draw(in: NSRect(x: (96 - extent.width) / 2, y: (96 - extent.height) / 2,
                              width: extent.width, height: extent.height),
                    from: .zero, operation: .sourceOver, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        var left = 96, top = 96, right = -1, bottom = -1
        for y in 0..<96 {
            for x in 0..<96 where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.02 {
                left = min(left, x); top = min(top, y); right = max(right, x); bottom = max(bottom, y)
            }
        }
        guard right >= left, bottom >= top,
              let cropped = bitmap.cgImage?.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)) else { return nil }
        let artwork = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        let factor = (size - 2) / max(artwork.size.width, artwork.size.height)
        let fitted = NSSize(width: artwork.size.width * factor, height: artwork.size.height * factor)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        artwork.draw(in: NSRect(x: (size - fitted.width) / 2, y: (size - fitted.height) / 2,
                               width: fitted.width, height: fitted.height),
                     from: .zero, operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
