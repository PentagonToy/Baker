import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Only a private, single-use pasteboard is accepted; URLs never name user files.
enum FormulaHandoff {
    static func pasteboardName(_ url: URL) -> NSPasteboard.Name? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "baker", parts.host == "formula", parts.path.isEmpty,
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              let items = parts.queryItems, items.count == 1, items[0].name == "pasteboard",
              let value = items[0].value, value.hasPrefix("deerstalker-formula-"),
              UUID(uuidString: String(value.dropFirst("deerstalker-formula-".count))) != nil else { return nil }
        return NSPasteboard.Name(value)
    }

    static func image(from data: Data) -> CGImage? {
        guard data.count <= 16 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) == UTType.png.identifier as CFString,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 12000, height <= 12000, width * height <= 12_000_000 else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

@MainActor extension Workbench {
    func receiveFormulaHandoff(_ url: URL) {
        guard let name = FormulaHandoff.pasteboardName(url) else { return }
        let board = NSPasteboard(name: name)
        defer { board.releaseGlobally() }
        guard !busy, !shuttingDown else {
            problem = "Baker is busy. Wait for the current operation, then select the formula again."; return
        }
        guard developerRuntimeOverrides || formulaSetup.ready else {
            problem = "Prepare formula recognition in Settings → Formula, then select the formula again."
            onFormulaSetupNeeded?(); return
        }
        guard let data = board.data(forType: .png), let image = FormulaHandoff.image(from: data) else {
            problem = "The selected formula image is unavailable or too large. Try a smaller region."; return
        }
        problem = nil
        formulaCapturePending = true
        startImport(asFormula: true, outputFormat: .latex) {
            try await self.importImage(image, notify: false)
        }
    }
}
