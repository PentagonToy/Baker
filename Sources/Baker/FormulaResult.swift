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
