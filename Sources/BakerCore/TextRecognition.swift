import Foundation
import Vision
import CoreText


public func recogniseText(_ url: URL, languages: [String] = ["ko-KR", "en-US"], finnish: Bool = false, tesseractPath: String = "") throws -> String {
    if finnish || OCRLanguages.usesTesseract(languages) {
        let text = try TesseractOCR.recognise(url, executable: tesseractPath, languages: finnish && !languages.contains("fi-FI") ? ["fi-FI"] : languages)
        guard !text.isEmpty else { throw BakerError(message: "No text was found. Check the region or image resolution.", code: .recognitionFailed) }; return text
    }
    let request = VNRecognizeTextRequest()
    try OCRLanguages.configure(request, languages: languages)
    try VNImageRequestHandler(url: url).perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    guard !text.isEmpty else { throw BakerError(message: "No text was found. Check the region or image resolution.", code: .recognitionFailed) }
    return text
}

/// Prepare Apple's accurate OCR with a generated sample, without reading a user capture.
public func prepareTextRecognition(languages: [String]) throws {
    guard !OCRLanguages.usesTesseract(languages),
          let context = CGContext(data: nil, width: 400, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 400, height: 100))
    context.textPosition = CGPoint(x: 20, y: 30)
    let sample = NSAttributedString(string: "Baker", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 40, nil), NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)])
    CTLineDraw(CTLineCreateWithAttributedString(sample), context)
    guard let image = context.makeImage() else { return }
    let request = VNRecognizeTextRequest()
    try OCRLanguages.configure(request, languages: languages)
    try VNImageRequestHandler(cgImage: image).perform([request])
}
