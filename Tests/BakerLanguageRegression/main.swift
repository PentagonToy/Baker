import BakerCore
import Foundation
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); checks += 1 }
check(OCRLanguages.choices.count == 6, "Six supported choices")
check(OCRLanguages.normalized([]) == ["en-US"], "At least one default")
check(OCRLanguages.normalized(["bad", "de-DE", "de-DE", "fi-FI"]) == ["de-DE", "fi-FI"], "Unknown and duplicate values removed")
check(OCRLanguages.normalized(OCRLanguages.choices.map(\.0)).count == 3, "Over-limit settings migrate to three")
check(OCRLanguages.setting("sv-SE", enabled: true, in: OCRLanguages.defaults) == OCRLanguages.defaults, "Fourth language rejected")
check(OCRLanguages.setting("en-US", enabled: false, in: ["en-US"]) == ["en-US"], "Last language retained")
let pair = OCRLanguages.setting("de-DE", enabled: false, in: OCRLanguages.defaults)
check(pair == ["en-US", "ko-KR"], "Deselect preserves remaining order")
check(OCRLanguages.setting("fi-FI", enabled: true, in: pair) == ["en-US", "ko-KR", "fi-FI"], "Finnish can join two choices")
check(OCRLanguages.setting("invalid", enabled: true, in: pair) == pair, "Unknown choice rejected")
for (code, _) in OCRLanguages.choices { check(OCRLanguages.tesseractCodes[code] != nil, "Every supported choice maps to a model") }
print("BakerLanguageRegression: \(checks) checks passed")
