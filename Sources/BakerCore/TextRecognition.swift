import Foundation
import Vision
import CoreText

public enum OCRLanguages {
    public static let maximumActive = 3
    public static let choices = [("en-US", "English"), ("de-DE", "Deutsch"), ("ko-KR", "한국어"), ("sv-SE", "Svenska"), ("da-DK", "Dansk"), ("fi-FI", "Suomi")]
    public static let defaults = ["en-US", "de-DE", "ko-KR"]
    public static let tesseractCodes = ["en-US": "eng", "de-DE": "deu", "ko-KR": "kor", "sv-SE": "swe", "da-DK": "dan", "fi-FI": "fin"]
    public static func normalized(_ languages: [String]) -> [String] {
        var seen = Set<String>()
        let valid = languages.filter { tesseractCodes[$0] != nil && seen.insert($0).inserted }
        return valid.isEmpty ? ["en-US"] : Array(valid.prefix(maximumActive))
    }
    public static func setting(_ code: String, enabled: Bool, in selection: [String]) -> [String] {
        var selected = normalized(selection)
        guard tesseractCodes[code] != nil else { return selected }
        if enabled { if !selected.contains(code), selected.count < maximumActive { selected.append(code) } }
        else if selected.count > 1 { selected.removeAll { $0 == code } }
        return selected
    }
    public static let supported: [String] = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? []
    public static func configure(_ request: VNRecognizeTextRequest, languages: [String]) throws {
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let supported = try request.supportedRecognitionLanguages()
        let selected = (languages.isEmpty ? [] : normalized(languages)).filter { supported.contains($0) }
        if !selected.isEmpty { request.recognitionLanguages = selected }
    }
}

public func recogniseText(_ url: URL, languages: [String] = ["ko-KR", "en-US"], finnish: Bool = false, tesseractPath: String = "") throws -> String {
    if finnish || languages.contains("fi-FI") {
        let text = try FinnishOCR.recognise(url, executable: tesseractPath, languages: languages.contains("fi-FI") ? languages : ["fi-FI"])
        guard !text.isEmpty else { throw BakerError(message: "No text was found. Check the region or image resolution.") }; return text
    }
    let request = VNRecognizeTextRequest()
    try OCRLanguages.configure(request, languages: languages)
    try VNImageRequestHandler(url: url).perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    guard !text.isEmpty else { throw BakerError(message: "No text was found. Check the region or image resolution.") }
    return text
}

/// Prepare Apple's accurate OCR with a generated sample, without reading a user capture.
public func prepareTextRecognition(languages: [String]) throws {
    guard !languages.contains("fi-FI"),
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
