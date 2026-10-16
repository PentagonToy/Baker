import BakerCore
import Foundation

struct FormulaRecognition: Sendable {
    let latex: String
    let confidence: Double?
}

func recogniseFormula(_ url: URL, python: String, config: String) throws -> String {
    try recogniseFormulaResult(url, python: python, config: config).latex
}

func recogniseFormulaResult(_ url: URL, python: String, config: String) throws -> FormulaRecognition {
    guard python.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: python),
          config.hasPrefix("/"), FileManager.default.fileExists(atPath: config) else {
        throw BakerError(message: "Set the formula Python executable and local model configuration in Settings.")
    }
    let workerURL = Bundle.main.bundleURL.pathExtension == "app"
        ? Bundle.main.url(forResource: "formula_worker", withExtension: "py")
        : Bundle.module.url(forResource: "formula_worker", withExtension: "py")
    guard let worker = workerURL else {
        throw BakerError(message: "The local formula worker is missing from Baker's resources.")
    }
    let response = try runProcess(URL(fileURLWithPath: python), arguments: ["-I", worker.path, url.path, config])
    struct Payload: Decodable { let latex: String?; let error: String?; let confidence: Double?; let confidence_method: String? }
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
    return FormulaRecognition(latex: latex, confidence: confidence)
}
