import BakerCore
import Foundation

struct FormulaRecognition: Sendable {
    let latex: String
    let confidence: Double?
    var model = "unknown"
    var confidenceMethod: String?
    var diagnostics: FormulaDiagnostics?
}

func decodeFormulaResponse(_ response: ProcessResult) throws -> FormulaRecognition {
    struct Payload: Decodable { let latex: String?; let error: String?; let error_code: String?; let confidence: Double?; let confidence_method: String?; let model: String?; let diagnostics: FormulaDiagnostics? }
    guard let payload = try? JSONDecoder().decode(Payload.self, from: response.output) else {
        throw BakerError(message: "Could not read the formula response. Check the local Python runtime and model files.", code: .invalidResponse, diagnostic: response.diagnostic)
    }
    if let error = payload.error {
        let code: BakerError.Code
        switch payload.error_code {
        case "formula_token_limit": code = .formulaTokenLimit
        case "recognition_timeout": code = .processTimedOut
        case "model_not_ready": code = .modelNotReady
        default: code = .recognitionFailed
        }
        throw BakerError(message: error, code: code)
    }
    guard response.status == 0, let source = payload.latex, !LatexWhitespace.compact(source).isEmpty else {
        throw BakerError(message: "The formula engine did not return LaTeX.", code: .recognitionFailed, diagnostic: response.diagnostic)
    }
    let confidence = payload.confidence.flatMap { value in
        payload.confidence_method == "geometric_mean_token_probability_v1" && value.isFinite && (0...1).contains(value) ? value : nil
    }
    let diagnostics = payload.diagnostics.flatMap { d -> FormulaDiagnostics? in
        guard confidence != nil, (1...512).contains(d.tokenCount), (0...d.tokenCount).contains(d.ambiguousTokenCount), d.minimumTokenProbability.isFinite, (0...1).contains(d.minimumTokenProbability) else { return nil }
        return d
    }
    return FormulaRecognition(latex: LatexWhitespace.compact(source), confidence: confidence, model: payload.model ?? "unknown", confidenceMethod: confidence == nil ? nil : payload.confidence_method, diagnostics: diagnostics)
}
