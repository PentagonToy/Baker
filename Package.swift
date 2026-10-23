// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Baker",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Baker", targets: ["Baker"]),
               .executable(name: "BakerRegression", targets: ["BakerRegression"]),
               .executable(name: "BakerPDFRegression", targets: ["BakerPDFRegression"]),
               .executable(name: "BakerRecordingRegression", targets: ["BakerRecordingRegression"]),
               .executable(name: "BakerCaptureRegression", targets: ["BakerCaptureRegression"]),
               .executable(name: "BakerClipboardRegression", targets: ["BakerClipboardRegression"]),
               .executable(name: "BakerFormulaRegression", targets: ["BakerFormulaRegression"]),
               .executable(name: "BakerScrollRegression", targets: ["BakerScrollRegression"]),
               .executable(name: "BakerLanguageRegression", targets: ["BakerLanguageRegression"])],
    targets: [
        .target(name: "BakerCore", resources: [.copy("Resources/Fonts"), .copy("Resources/Tessdata")]),
        .executableTarget(name: "Baker", dependencies: ["BakerCore"], resources: [.copy("Resources/FormulaPreview"), .copy("Resources/formula_worker.py"), .copy("Resources/texo_worker.py"), .copy("Resources/formula_model_install.py"), .copy("Resources/texo-model.json"), .copy("Resources/image_tools_worker.py"), .copy("Resources/document_worker.py"), .copy("Resources/document_reconstruction.py"), .copy("Resources/formula-model.json"), .copy("Resources/formula-model-canonical.json"), .copy("Resources/pdf-engine.json"), .copy("Resources/pdf_engine_install.py")]),
        .executableTarget(name: "BakerRegression", dependencies: ["BakerCore"], path: "Tests/BakerRegression"),
        .executableTarget(name: "BakerPDFRegression", dependencies: ["BakerCore"], path: "Tests/BakerPDFRegression"),
        .executableTarget(name: "BakerRecordingRegression", dependencies: ["BakerCore"], path: "Tests/BakerRecordingRegression"),
        .executableTarget(name: "BakerCaptureRegression", dependencies: ["BakerCore"], path: "Tests/BakerCaptureRegression"),
        .executableTarget(name: "BakerClipboardRegression", dependencies: ["BakerCore"], path: "Tests/BakerClipboardRegression"),
        .executableTarget(name: "BakerFormulaRegression", dependencies: ["BakerCore"], path: "Tests/BakerFormulaRegression"),
        .executableTarget(name: "BakerScrollRegression", dependencies: ["BakerCore"], path: "Tests/BakerScrollRegression"),
        .executableTarget(name: "BakerLanguageRegression", dependencies: ["BakerCore"], path: "Tests/BakerLanguageRegression")
    ]
)
