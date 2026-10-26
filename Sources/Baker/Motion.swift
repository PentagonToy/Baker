import SwiftUI

/// Short state transitions only; reduced motion disables them completely.
enum BakerMotion {
    static func selection(reduced: Bool) -> Animation? { reduced ? nil : .easeInOut(duration: 0.16) }
}
