import Foundation
import Vision

public enum OCRLanguages {
    public static let maximumActive = 5
    public static let choices = [
        ("en-US", "English"), ("de-DE", "German — Deutsch"), ("ko-KR", "Korean — 한국어"),
        ("ar-SA", "Arabic — العربية"), ("es-ES", "Spanish — Español"), ("fr-FR", "French — Français"),
        ("fa-IR", "Persian — فارسی"), ("zh-Hans", "Chinese (Simplified) — 简体中文"),
        ("zh-Hant", "Chinese (Traditional) — 繁體中文"), ("ja-JP", "Japanese — 日本語"),
        ("sv-SE", "Swedish — Svenska"), ("da-DK", "Danish — Dansk"), ("fi-FI", "Finnish — Suomi")
    ]
    public static let defaults = ["en-US", "de-DE", "ko-KR"]
    public static let tesseractCodes = ["en-US": "eng", "de-DE": "deu", "ko-KR": "kor", "sv-SE": "swe", "da-DK": "dan", "fi-FI": "fin", "ar-SA": "ara", "es-ES": "spa", "fr-FR": "fra", "fa-IR": "fas", "zh-Hans": "chi_sim", "zh-Hant": "chi_tra", "ja-JP": "jpn"]
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
    /// Use a single local engine for the whole selection, preserving mixed-language order.
    public static func usesTesseract(_ languages: [String], visionSupported: [String] = supported) -> Bool {
        normalized(languages).contains { $0 == "fi-FI" || !visionSupported.contains($0) }
    }
    public static let supported: [String] = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? []
    public static func configure(_ request: VNRecognizeTextRequest, languages: [String]) throws {
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let supported = try request.supportedRecognitionLanguages()
        let selected = languages.isEmpty ? [] : normalized(languages)
        guard selected.allSatisfy({ supported.contains($0) }) else {
            throw BakerError(message: "A selected language needs local Tesseract recognition.", code: .modelNotReady, recovery: .captureSettings)
        }
        if !selected.isEmpty { request.recognitionLanguages = selected }
    }
}

