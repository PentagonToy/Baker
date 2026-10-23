import Foundation
import BakerCore

enum FormulaEngine: String, CaseIterable, Sendable {
    case mfr, texo
    var title: String { self == .mfr ? "Pix2Text" : "Texo · Preview" }
    var summary: String { self == .mfr ? "Lower memory use. A balanced starting point." : "Faster recognition in our tests, with higher memory use. Experimental." }
    var resource: String { self == .mfr ? "formula-model" : "texo-model" }
    func directoryName(variant: String?) -> String {
        self == .texo ? "texo-transfer-v1" : (variant == "mlp-int8-v1" ? "mfr-1.5-mlp-int8-v1" : "mfr-1.5")
    }
    func settings(directory: URL) -> [String: Any] {
        ["model_dir": directory.path, "engine": rawValue, "threads": 2, "max_new_tokens": self == .texo ? 512 : 256, "timeout_seconds": 45, "max_image_pixels": 12000000]
    }
    var bundledPaths: [String] { self == .mfr ? ["Runtime/mfr", "DocumentEngine/mfr"] : ["Runtime/texo"] }
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
        guard value.variant == nil || (self == .mfr && value.variant == "mlp-int8-v1" && (value.bundledOnly == true || value.archive != nil)) else {
            throw BakerError(message: "The formula model variant is unsupported. Reinstall Baker.", code: .configurationInvalid, recovery: .updateApp)
        }
        return value
    }
}
