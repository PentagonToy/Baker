import AppKit
import CoreText

public enum MathFont: String, CaseIterable {
    case latinModern = "Latin Modern Math"
    case termes = "TeX Gyre Termes Math"
    case pagella = "TeX Gyre Pagella Math"
    case stixTwo = "STIX Two Math"
    case stix = "STIX"

    private static let registered: Void = {
        let bundle = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
        for name in ["latinmodern-math", "texgyretermes-math", "texgyrepagella-math"] {
            if let url = bundle.url(forResource: name, withExtension: "otf", subdirectory: "Fonts") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    public var bundledFontURL: URL? {
        let name: String
        switch self { case .latinModern: name = "latinmodern-math"; case .termes: name = "texgyretermes-math"; case .pagella: name = "texgyrepagella-math"; default: return nil }
        let bundle = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
        return bundle.url(forResource: name, withExtension: "otf", subdirectory: "Fonts")
    }

    public var installedFont: NSFont? {
        _ = Self.registered
        let names: [String]
        switch self {
        case .stixTwo: names = ["STIXTwoMath-Regular", "STIX Two Math"]
        case .stix: names = ["STIXGeneral-Regular", "STIXGeneral"]
        case .latinModern: names = ["LatinModernMath-Regular", "LatinModernMath", "Latin Modern Math"]
        case .termes: names = ["TeXGyreTermesMath-Regular", "TeX Gyre Termes Math"]
        case .pagella: names = ["TeXGyrePagellaMath-Regular", "TeX Gyre Pagella Math"]
        }
        return names.lazy.compactMap { NSFont(name: $0, size: 18) }.first
    }

    public var resolvedFont: NSFont {
        installedFont ?? MathFont.stixTwo.installedFont ?? MathFont.stix.installedFont ?? .systemFont(ofSize: 18)
    }
}

/// Both representations belong to one pasteboard item, so consumers choose either
/// editable Unicode or the same text with the selected mathematical font.
public enum MathClipboard {
    public static func item(text: String, font: MathFont) throws -> NSPasteboardItem {
        let attributed = NSAttributedString(string: text, attributes: [.font: font.resolvedFont])
        let rtf = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(rtf, forType: .rtf)
        return item
    }
}
