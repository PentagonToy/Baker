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
        .executableTarget(name: "Baker", dependencies: ["BakerCore"], resources: [.copy("Resources/formula_worker.py"), .copy("Resources/document_worker.py"), .copy("Resources/document_reconstruction.py"), .copy("Resources/formula-model.json")]),
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
