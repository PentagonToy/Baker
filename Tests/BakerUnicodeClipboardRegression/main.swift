import BakerCore
import AppKit

// Bind the unchanged clipboard implementation to the existing app's font resources.
// This creates pasteboard items but never writes to the user's clipboard or installs fonts.
extension Bundle {
    static var module: Bundle { Bundle(path: CommandLine.arguments[2])! }
}
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let results = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
var checks = 0
for row in results {
    for key in ["plain", "styled"] {
        let text = row[key] as! String
        for font in MathFont.allCases {
            let item = try MathClipboard.item(text: text, font: font)
            precondition(item.string(forType: .string) == text, "Plain clipboard text changed")
            let decoded = try NSAttributedString(data: item.data(forType: .rtf)!, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
            precondition(decoded.string == text, "RTF clipboard text changed: " + text)
            checks += 1
        }
    }
}
print("Passed \(checks) plain/RTF round trips for \(results.count) inputs, two modes and five font choices")
