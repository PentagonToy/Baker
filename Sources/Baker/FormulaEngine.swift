import Foundation
import BakerCore

enum FormulaEngine: String, CaseIterable, Sendable {
    case mfr, texo, plusS = "plus-s"
    var title: String {
        switch self { case .mfr: return "Pix2Text"; case .texo: return "Texo"; case .plusS: return "PP-FormulaNet plus-S" }
    }
    var summary: String {
        switch self {
        case .mfr: return "A balanced choice for everyday formulas."
        case .texo: return "Fast recognition with low memory use in our tests."
        case .plusS: return "An alternative for multiline formulas. Uses more memory; review the result."
        }
    }
    var resource: String {
        switch self { case .mfr: return "formula-model"; case .texo: return "texo-model"; case .plusS: return "plus-s-model" }
    }
    func directoryName(variant: String?) -> String {
        switch self {
        case .texo: return "texo-transfer-v1"
        case .plusS: return "pp-formulanet-plus-s-fp32-v1"
        case .mfr: return variant == "mlp-int8-v1" ? "mfr-1.5-mlp-int8-v1" : "mfr-1.5"
        }
    }
    func settings(directory: URL) -> [String: Any] {
        ["model_dir": directory.path, "engine": rawValue, "threads": 2, "max_new_tokens": self == .plusS ? 1024 : (self == .texo ? 512 : 256), "timeout_seconds": 45, "max_image_pixels": 12000000]
    }
    var bundledPaths: [String] {
        switch self { case .mfr: return ["Runtime/mfr", "DocumentEngine/mfr"]; case .texo: return ["Runtime/texo"]; case .plusS: return [] }
    }
    static func cachedMFRVariant(root: URL) -> String? {
        let files = FileManager.default
        if files.fileExists(atPath: root.appendingPathComponent("mfr-1.5/baker-config.json").path) { return "fp32" }
        if files.fileExists(atPath: root.appendingPathComponent("mfr-1.5-mlp-int8-v1/baker-config.json").path) { return "mlp-int8-v1" }
        return (try? FormulaEngine.mfr.manifest())?.variant
    }
    func manifest(variant: String? = nil) throws -> FormulaModelManifest {
        let bundle = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
        let name = self == .mfr && variant == "fp32" ? "formula-model-canonical" : resource
        guard let source = bundle.url(forResource: name, withExtension: "json") else {
            throw BakerError(message: "Baker's model download information is missing. Reinstall Baker.", code: .configurationInvalid, recovery: .updateApp)
        }
        let value = try JSONDecoder().decode(FormulaModelManifest.self, from: Data(contentsOf: source))
        guard value.variant == nil || (self == .mfr && value.variant == "mlp-int8-v1" && (value.bundledOnly == true || value.archive != nil)) || (self == .plusS && value.variant == "fp32-ort-v1" && value.archive != nil) else {
            throw BakerError(message: "The formula model variant is unsupported. Reinstall Baker.", code: .configurationInvalid, recovery: .updateApp)
        }
        return value
    }
}
