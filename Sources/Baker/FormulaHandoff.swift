import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Only a private, single-use pasteboard is accepted; URLs never name user files.
enum FormulaHandoff {
    static func respond(on board: NSPasteboard, latex: String? = nil, error: String? = nil) {
        guard board.data(forType: .png) != nil,
              let data = try? JSONSerialization.data(withJSONObject: latex.map { ["latex": $0] } ?? ["error": error ?? "Recognition failed."]),
              let text = String(data: data, encoding: .utf8) else { return }
        // Take ownership before replacing another application's PNG with a result.
        board.clearContents()
        board.setString(text, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { board.releaseGlobally() }
    }

    /// Conservative guard against converting an accidentally selected prose line.
    static func isFormula(_ latex: String) -> Bool {
        let maths = latex.replacingOccurrences(of: #"\\(?:text|textrm|mathrm|operatorname)\{[^{}]*\}"#, with: "", options: .regularExpression)
        return maths.range(of: #"[=+*/<>^_−±≤≥∑∫√]|\\(?:frac|sqrt|sum|int|prod|lim|sin|cos|tan|log|ln|alpha|beta|gamma|delta|theta|lambda|mu|nu|pi|rho|sigma|tau|phi|psi|omega)\b"#, options: .regularExpression) != nil
    }
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
    func receiveFormulaHandoff(_ url: URL) async {
        guard let name = FormulaHandoff.pasteboardName(url) else { return }
        let board = NSPasteboard(name: name)
        guard !busy, !shuttingDown else {
            FormulaHandoff.respond(on: board, error: "Formula recognition is busy. Try again when it finishes."); return
        }
        guard developerRuntimeOverrides || formulaSetup.ready else {
            FormulaHandoff.respond(on: board, error: "Prepare formula recognition in Baker Settings → Formula, then try again."); return
        }
        guard let data = board.data(forType: .png), FormulaHandoff.image(from: data) != nil else {
            FormulaHandoff.respond(on: board, error: "The selected formula image is unavailable or too large."); return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("baker-formula-" + UUID().uuidString)
        busy = true
        defer { busy = false; try? FileManager.default.removeItem(at: directory) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let image = directory.appendingPathComponent("formula.png")
            try data.write(to: image, options: .atomic)
            let request = RecognitionRequest(url: image, formula: true, python: developerRuntimeOverrides ? python : formulaSetup.python,
                                            configuration: developerRuntimeOverrides ? config : formulaSetup.configuration,
                                            languages: [], finnish: false, tesseract: "")
            let result = try await recognitionFlow.recognise(request)
            try Task.checkCancellation()
            guard FormulaHandoff.isFormula(result.latex) else {
                FormulaHandoff.respond(on: board, error: "No clear formula was recognised. Select only the equation; ordinary text uses Copy."); return
            }
            FormulaHandoff.respond(on: board, latex: result.latex)
        } catch {
            FormulaHandoff.respond(on: board, error: error.localizedDescription)
        }
    }
}
