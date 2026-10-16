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
    var format: OutputFormat = .latex
    var style: LatexCopyStyle = .bare
    var preview: NSImage?
    var previewError: String?
    var error = ""
    var copyStatus = ""
}
