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
        let cacheKey = "\(folder)/\(name)/\(size)"
        if let cached = templates[cacheKey] { return cached }
        let image: NSImage?
        if let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: folder), let custom = NSImage(contentsOf: url) {
            // Give AppKit menus a concrete alpha mask rather than a deferred SVG representation.
            let rendered = NSImage(size: NSSize(width: size, height: size))
            rendered.lockFocus()
            custom.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1)
            rendered.unlockFocus()
            image = rendered
        } else { image = NSImage(systemSymbolName: fallback, accessibilityDescription: nil) }
        image?.size = NSSize(width: size, height: size)
        image?.isTemplate = true
        if let image { templates[cacheKey] = image }
        return image
    }
    static func system(_ name: String, size: CGFloat = 18) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.size = NSSize(width: size, height: size); image?.isTemplate = true
        return image
    }
}
