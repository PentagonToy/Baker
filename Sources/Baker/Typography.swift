import SwiftUI

/// A shared minimum for readable controls and supporting text in Baker windows.
enum BakerTypography {
    static let body = Font.system(size: 14)
    static let supporting = Font.system(size: 13)
    static let section = Font.system(size: 14, weight: .semibold)
    static let sidebar = Font.system(size: 14, weight: .medium)
}
