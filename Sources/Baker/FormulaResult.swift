import AppKit
import BakerCore

enum OutputFormat: String, CaseIterable { case text = "Text", latex = "LaTeX", markdown = "Markdown", keynote = "Keynote", unicode = "Unicode" }
enum CaptureAction { case image, text, formula, unicode }

struct FormulaResult {
    enum Phase { case recognising, ready, failed }
    var phase: Phase = .recognising
    var confidence: Double?
    var originalConfidence: Double?
    var wasEdited = false
    var originalLatex = ""
    var model = "unknown"
    var recognitionProvider: String? {
        guard model != "unknown", !model.isEmpty else { return nil }
        let local = ["pix2text", "texo-", "pp-formulanet-", "Baker · Local"].contains { model.hasPrefix($0) }
        return local ? "Baker · Local" : "Saved result"
    }
    var confidenceMethod: String?
    var diagnostics: FormulaDiagnostics?
    var unicodeOverride: String?
    var latex = ""
    var unicode = ""
    var keynote = ""
    var keynoteWarning = ""
    var warning = ""
    // Layout and font approximations are informational, not conversion failures.
    var unicodeUnavailable: Bool { phase == .ready && unicode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !latex.isEmpty }
    var format: OutputFormat = .latex
    var style: LatexCopyStyle = .bare
    var preview: NSImage?
    var previewError: String?
    var failure: BakerError?
    var error = ""
    var copiedFormat: OutputFormat?
    var copyStatus = ""
}

/// History uses the same destination conversions as the detail view, without reopening it.
enum FormulaHistoryOutput {
    static func text(latex: String, unicode: String?, style: LatexCopyStyle, format: OutputFormat) -> String {
        switch format {
        case .latex: return style.format(latex)
        case .markdown: return LatexCopyStyle.displayDollar.format(latex)
        case .keynote: return LatexWhitespace.compact(KeynoteLatex.convert(latex).text)
        case .unicode: return unicode ?? UnicodeMath.approximate(latex, italicVariables: true).text
        case .text: return ""
        }
    }
}
