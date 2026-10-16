import Foundation
import CoreGraphics
import ImageIO

public enum FinnishOCR {
    public static var defaultExecutable: String {
        [Bundle.main.resourceURL?.appendingPathComponent("Runtime/tesseract/bin/tesseract").path ?? "", "/opt/homebrew/bin/tesseract", "/usr/local/bin/tesseract"].first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }
    private static var models: URL? {
        let bundle = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
        return bundle.url(forResource: "Tessdata", withExtension: nil)
    }
    public static func recognise(_ image: URL, executable: String = "", languages: [String] = ["fi-FI"]) throws -> String {
        try Task.checkCancellation()
        if ["heic", "heif"].contains(image.pathExtension.lowercased()) {
            guard let source = CGImageSourceCreateWithURL(image as CFURL, nil), let raster = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw BakerError(message: "Could not read this HEIC image for Finnish OCR.") }
            return try recognise(raster, executable: executable, languages: languages)
        }
        let executable = executable.isEmpty ? defaultExecutable : executable
        guard executable.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executable) else {
            throw BakerError(message: "Finnish OCR needs a local Tesseract executable. Choose it in Settings → Advanced, or deselect Finnish.")
        }
        let selected = OCRLanguages.normalized(languages).compactMap { OCRLanguages.tesseractCodes[$0] }
        guard let models, selected.allSatisfy({ FileManager.default.fileExists(atPath: models.appendingPathComponent($0 + ".traineddata").path) }) else {
            throw BakerError(message: "A selected bundled OCR language model is missing.")
        }
        let response = try runProcess(URL(fileURLWithPath: executable), arguments: [image.path, "stdout", "--tessdata-dir", models.path, "-l", selected.joined(separator: "+"), "--oem", "1", "--psm", "3"], timeout: 60, environment: ["OMP_THREAD_LIMIT": "2", "OMP_NUM_THREADS": "2"])
        guard response.status == 0, response.output.count <= 1_048_576, let text = String(data: response.output, encoding: .utf8) else {
            throw BakerError(message: "Finnish OCR failed. Check the Tesseract executable and image.")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func recognise(_ image: CGImage, executable: String = "", languages: [String] = ["fi-FI"]) throws -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("baker-finnish-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("page.png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { throw BakerError(message: "Could not prepare the scanned page for Finnish OCR.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw BakerError(message: "Could not encode the scanned page for Finnish OCR.") }
        return try recognise(url, executable: executable, languages: languages)
    }
}
