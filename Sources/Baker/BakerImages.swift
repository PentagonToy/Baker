import AppKit

/// Authoring sources stay under others/assests; packaging copies their rendered resources.
@MainActor
enum BakerImages {
    static func appIcon(dark: Bool) -> NSImage? {
        guard let url = Bundle.main.url(forResource: dark ? "baker_icon_dark" : "baker_icon_light",
                                        withExtension: "svg", subdirectory: "BakerIcons") else { return nil }
        return NSImage(contentsOf: url)
    }

    static func template(_ name: String, folder: String = "BakerSymbols", fallback: String, size: CGFloat = 18) -> NSImage? {
        let image: NSImage?
        if let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: folder), let custom = NSImage(contentsOf: url) {
            image = custom
        } else { image = NSImage(systemSymbolName: fallback, accessibilityDescription: nil) }
        image?.size = NSSize(width: size, height: size)
        image?.isTemplate = true
        return image
    }
    static func system(_ name: String, size: CGFloat = 18) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.size = NSSize(width: size, height: size); image?.isTemplate = true
        return image
    }
}
