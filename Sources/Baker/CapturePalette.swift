import AppKit
import SwiftUI

/// Okabe–Ito's eight colour values; white is a separate masking utility.
/// Reference: Masataka Okabe and Kei Ito, https://jfly.uni-koeln.de/color/.
enum CaptureColour: String, CaseIterable, Identifiable {
    case black = "#000000", orange = "#E69F00", skyBlue = "#56B4E9", bluishGreen = "#009E73"
    case yellow = "#F0E442", blue = "#0072B2", vermillion = "#D55E00", reddishPurple = "#CC79A7", white = "#FFFFFF"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .black: return "Black"
        case .orange: return "Orange"
        case .skyBlue: return "Sky blue"
        case .bluishGreen: return "Bluish green"
        case .yellow: return "Yellow"
        case .blue: return "Blue"
        case .vermillion: return "Vermillion"
        case .reddishPurple: return "Reddish purple"
        case .white: return "White · mask"
        }
    }
    var nsColor: NSColor {
        let value = UInt32(rawValue.dropFirst(), radix: 16)!
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    var colour: Color { Color(nsColor: nsColor) }
    var checkColour: Color { [.black, .blue].contains(self) ? .white : .black }
}
