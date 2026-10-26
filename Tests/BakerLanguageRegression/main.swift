import BakerCore
import Foundation
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); checks += 1 }
check(OCRLanguages.choices.count == 13, "Thirteen language choices")
check(OCRLanguages.normalized([]) == ["en-US"], "At least one default")
check(OCRLanguages.normalized(["bad", "de-DE", "de-DE", "fi-FI"]) == ["de-DE", "fi-FI"], "Unknown and duplicate values removed")
check(OCRLanguages.normalized(OCRLanguages.choices.map(\.0)).count == 5, "Over-limit settings migrate to five")
check(OCRLanguages.setting("sv-SE", enabled: true, in: OCRLanguages.defaults) == OCRLanguages.defaults + ["sv-SE"], "Fourth language accepted")
check(OCRLanguages.setting("en-US", enabled: false, in: ["en-US"]) == ["en-US"], "Last language retained")
let pair = OCRLanguages.setting("de-DE", enabled: false, in: OCRLanguages.defaults)
check(pair == ["en-US", "ko-KR"], "Deselect preserves remaining order")
check(OCRLanguages.setting("fi-FI", enabled: true, in: pair) == ["en-US", "ko-KR", "fi-FI"], "Finnish can join two choices")
check(OCRLanguages.setting("invalid", enabled: true, in: pair) == pair, "Unknown choice rejected")
for (code, _) in OCRLanguages.choices { check(OCRLanguages.tesseractCodes[code] != nil, "Every supported choice maps to a model") }


let five = OCRLanguages.defaults + ["es-ES", "fr-FR"]
check(OCRLanguages.setting("ja-JP", enabled: true, in: five) == five, "Sixth language rejected")
check(!OCRLanguages.usesTesseract(["ar-SA", "ja-JP"], visionSupported: ["ar-SA", "ja-JP"]), "Native multilingual selection")
check(OCRLanguages.usesTesseract(["fa-IR", "en-US"], visionSupported: ["en-US"]), "Persian uses complete local selection")
check(OCRLanguages.usesTesseract(["fi-FI"], visionSupported: ["fi-FI"]), "Finnish compatibility preserved")
check(OCRLanguages.usesTesseract(["ar-SA"], visionSupported: []), "OS capability fallback")
check(OCRLanguages.choices.first { $0.0 == "ko-KR" }?.1 == "Korean — 한국어", "Bilingual label")
print("BakerLanguageRegression: \(checks) checks passed")
