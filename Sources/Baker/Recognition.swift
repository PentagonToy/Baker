import BakerCore
import Foundation

func recogniseFormula(_ url: URL, python: String, config: String) throws -> String {
    try recogniseFormulaResult(url, python: python, config: config).latex
}

func recogniseFormulaResult(_ url: URL, python: String, config: String) throws -> FormulaRecognition {
    guard python.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: python),
          config.hasPrefix("/"), FileManager.default.fileExists(atPath: config) else {
        throw BakerError(message: "Formula recognition is not ready. Open Settings → Formula to prepare it.", code: .modelNotReady)
    }
    let workerURL = Bundle.main.bundleURL.pathExtension == "app"
        ? Bundle.main.url(forResource: "formula_worker", withExtension: "py")
        : Bundle.module.url(forResource: "formula_worker", withExtension: "py")
    guard let worker = workerURL else {
        throw BakerError(message: "The local formula worker is missing from Baker's resources.", code: .modelNotReady, recovery: .updateApp)
    }
    let response = try runProcess(URL(fileURLWithPath: python), arguments: ["-I", "-B", worker.path, url.path, config])
    return try decodeFormulaResponse(response)
}


@MainActor extension RecognitionCoordinator {
    convenience init() {
        self.init(recogniser: { request in
            request.formula ? try recogniseFormulaResult(request.url, python: request.python, config: request.configuration)
                : FormulaRecognition(latex: try recogniseText(request.url, languages: request.languages, finnish: request.finnish, tesseractPath: request.tesseract), confidence: nil)
        }, renderer: { try await FormulaPreviewRenderer.shared.render($0) })
    }
}
