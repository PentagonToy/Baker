import Foundation
import Vision

public func recogniseText(_ url: URL) throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.automaticallyDetectsLanguage = true
    let supported = try request.supportedRecognitionLanguages()
    request.recognitionLanguages = ["ko-KR", "en-US"].filter { supported.contains($0) }
    try VNImageRequestHandler(url: url).perform([request])
    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    guard !text.isEmpty else { throw BakerError(message: "No text was found. Check the region or image resolution.") }
    return text
}
