import AppKit

public enum MathFont: String, CaseIterable {
    case stixTwo = "STIX Two Math"
    case stix = "STIX"
    case latinModern = "Latin Modern Math"

    public var installedFont: NSFont? {
        let names: [String]
        switch self {
        case .stixTwo: names = ["STIXTwoMath-Regular", "STIX Two Math"]
        case .stix: names = ["STIXGeneral-Regular", "STIXGeneral"]
        case .latinModern: names = ["LatinModernMath-Regular", "Latin Modern Math"]
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
