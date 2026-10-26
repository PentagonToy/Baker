struct RecognitionRequest: Sendable { let url: URL; let formula: Bool }
struct FormulaRecognition: Sendable { let latex: String; let confidence: Double?; var model = "unknown" }
struct FormulaResult { var model = "unknown" }
@MainActor final class FakePlugins {
    struct Entry { let manifest: OCRPluginManifest }
    var entry: Entry?
    var cancelled = false, fail = false
    var message = "", calls = 0
    func selected(for operation: String) -> Entry? { entry }
    func run(_ entry: Entry, operation: String, input: URL?, destination: URL? = nil, format: PDFExportFormat? = nil) async throws -> OCRPluginExecution {
        calls += 1
        if cancelled { throw CancellationError() }
        if fail { throw BakerError(message: "Synthetic failure", code: .invalidResponse) }
        return OCRPluginExecution(latex: "plugin", report: PDFConversionReport(destination: destination ?? input!, format: format ?? .markdown, pages: [], bytesWritten: 0, warnings: [], provider: entry.manifest.label))
    }
}
@MainActor final class FakeRecognition {
    var calls = 0
    func recognise(_ request: RecognitionRequest) async throws -> FormulaRecognition { calls += 1; return FormulaRecognition(latex: "local", confidence: nil) }
}
@MainActor final class FakeDocument {
    var calls = 0
    func convert(source: URL, destination: URL, format: PDFExportFormat, options: PDFConversionOptions, progress: @escaping @MainActor (PDFConversionProgress) -> Void) async throws -> PDFConversionReport {
        calls += 1
        return PDFConversionReport(destination: destination, format: format, pages: [], bytesWritten: 0, warnings: [])
    }
}
@MainActor final class FakeUsage { var calls = 0; func record(pages: Int? = nil) { calls += 1 } }
struct FakeSetup { var ready = true }
@MainActor final class Workbench {
    let plugins = FakePlugins(), recognitionFlow = FakeRecognition(), documentFlow = FakeDocument(), usage = FakeUsage()
    var formulaSetup = FakeSetup(), developerRuntimeOverrides = false, formulaResults: [UUID: FormulaResult] = [:]
    var preparedDocumentEngine: PDFDocumentEngine? = PDFDocumentEngine(python: URL(fileURLWithPath: "/unused"), worker: URL(fileURLWithPath: "/unused"), configuration: URL(fileURLWithPath: "/unused"))
}
@MainActor func routingChecks() async throws {
    let m = Workbench(), input = URL(fileURLWithPath: "/synthetic")
    let manifest = OCRPluginManifest(schema: 1, id: "example.test", name: "Example", version: "1", executable: "baker-python", arguments: [], operations: ["formula", "pdf"], timeoutSeconds: 1)
    m.plugins.entry = FakePlugins.Entry(manifest: manifest)
    let request = RecognitionRequest(url: input, formula: true)
    let pluginFormula = try await m.recogniseInput(request)
    precondition(pluginFormula.latex == "plugin")
    precondition(m.usage.calls == 0 && m.recognitionFlow.calls == 0)
    m.plugins.fail = true
    let localFormula = try await m.recogniseInput(request)
    precondition(localFormula.latex == "local")
    precondition(m.usage.calls == 1 && m.recognitionFlow.calls == 1)
    m.plugins.cancelled = true
    do { _ = try await m.recogniseInput(request); fatalError("Cancellation accepted") } catch is CancellationError {}
    precondition(m.recognitionFlow.calls == 1)
    m.plugins.cancelled = false; m.formulaSetup.ready = false
    do { _ = try await m.recogniseInput(request); fatalError("Missing fallback accepted") } catch {}
    precondition(m.recognitionFlow.calls == 1)
    var options = PDFConversionOptions(); options.documentEngine = m.preparedDocumentEngine
    let report = try await m.convertDocument(source: input, destination: input, format: .markdown, options: options) { _ in }
    precondition(report.provider == "Baker · Local" && m.documentFlow.calls == 1)
    m.plugins.cancelled = true
    do { _ = try await m.convertDocument(source: input, destination: input, format: .markdown, options: options) { _ in }; fatalError("Cancellation accepted") } catch is CancellationError {}
    precondition(m.documentFlow.calls == 1)
    m.plugins.fail = false; m.plugins.cancelled = false
    let pluginReport = try await m.convertDocument(source: input, destination: input, format: .markdown, options: options) { _ in }
    precondition(pluginReport.provider == manifest.label && m.documentFlow.calls == 1 && m.usage.calls == 2)
    print("Plugin routing passed: success, fallback, cancellation and missing local model")
}
Task { @MainActor in do { try await routingChecks(); exit(0) } catch { print(error); exit(1) } }
dispatchMain()
