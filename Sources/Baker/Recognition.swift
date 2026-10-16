import BakerCore
import Foundation

struct FormulaRecognition: Sendable {
    let latex: String
    let confidence: Double?
    var model = "unknown"
    var confidenceMethod: String?
    var diagnostics: FormulaDiagnostics?
}

func recogniseFormula(_ url: URL, python: String, config: String) throws -> String {
    try recogniseFormulaResult(url, python: python, config: config).latex
}

func recogniseFormulaResult(_ url: URL, python: String, config: String) throws -> FormulaRecognition {
    guard python.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: python),
          config.hasPrefix("/"), FileManager.default.fileExists(atPath: config) else {
        throw BakerError(message: "Formula recognition is not ready. Open Settings → Formula to prepare it.")
    }
    let workerURL = Bundle.main.bundleURL.pathExtension == "app"
        ? Bundle.main.url(forResource: "formula_worker", withExtension: "py")
        : Bundle.module.url(forResource: "formula_worker", withExtension: "py")
    guard let worker = workerURL else {
        throw BakerError(message: "The local formula worker is missing from Baker's resources.")
    }
    let response = try runProcess(URL(fileURLWithPath: python), arguments: ["-I", "-B", worker.path, url.path, config])
    struct Payload: Decodable { let latex: String?; let error: String?; let confidence: Double?; let confidence_method: String?; let model: String?; let diagnostics: FormulaDiagnostics? }
    guard let payload = try? JSONDecoder().decode(Payload.self, from: response.output) else {
        throw BakerError(message: "Could not read the formula response. Check the local Python runtime and model files.")
    }
    if let error = payload.error { throw BakerError(message: error) }
    guard response.status == 0, let latex = payload.latex, !latex.isEmpty else {
        throw BakerError(message: "The formula engine did not return LaTeX.")
    }
    let confidence = payload.confidence.flatMap { value in
        payload.confidence_method == "geometric_mean_token_probability_v1" && value.isFinite && (0...1).contains(value) ? value : nil
    }
    let diagnostics = payload.diagnostics.flatMap { d -> FormulaDiagnostics? in
        guard confidence != nil, (1...512).contains(d.tokenCount), (0...d.tokenCount).contains(d.ambiguousTokenCount), d.minimumTokenProbability.isFinite, (0...1).contains(d.minimumTokenProbability) else { return nil }
        return d
    }
    return FormulaRecognition(latex: LatexWhitespace.compact(latex), confidence: confidence, model: payload.model ?? "unknown", confidenceMethod: confidence == nil ? nil : payload.confidence_method, diagnostics: diagnostics)
}
