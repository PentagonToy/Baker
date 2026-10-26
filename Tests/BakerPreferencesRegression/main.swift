import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); checks += 1 }
let suite = "Baker.PreferencesRegression." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let store = BakerPreferences(defaults: defaults)
check(store[PreferenceKeys.copyCapturedImages], "Image copying defaults on")
check(store[PreferenceKeys.copyRecognisedText], "Text copying defaults on")
check(!store[PreferenceKeys.showResults], "Result window defaults off")
check(store[PreferenceKeys.visibleCaptures] == 0, "Previews fit the screen by default")
check(store[PreferenceKeys.formulaHistoryLimit] == 50, "History default retained")
check(store[PreferenceKeys.imageHistoryLimit] == 0, "Images default to no count limit")
check(store[PreferenceKeys.imageHistoryDays] == 0, "Images default to no age limit")
check(store[PreferenceKeys.imageHistoryApprovedDirectory].isEmpty, "No directory approved for automatic removal by default")
check(store[PreferenceKeys.appearance] == "system", "System theme default")
check(store.captureDirectory == nil, "Unconfigured directory remains absent")
defaults.set("relative/path", forKey: "storageDirectory")
check(store.captureDirectory == nil, "Malformed relative path is not used")
store[PreferenceKeys.storageDirectory] = "/tmp/Baker"
check(store.captureDirectory?.path == "/tmp/Baker", "Absolute storage path round trip")
store[PreferenceKeys.copyCapturedImages] = false
check(defaults.object(forKey: "copyCapturedImages") as? Bool == false, "Existing persisted name retained")
defaults.set("Dark", forKey: "mathFont")
check(store[PreferenceKeys.mathFont] == "Dark", "Store does not rewrite unrelated strings")
defaults.set("invalid", forKey: "visibleCaptures")
check(store[PreferenceKeys.visibleCaptures] == 0, "Wrong type uses typed default")
store[PreferenceKeys.menuLayout] = Data([1,2,3])
check(store[PreferenceKeys.menuLayout] == Data([1,2,3]), "Data preference retains bytes")
store[PreferenceKeys.hasOfferedLaunchAtLogin] = true
store.migrate()
check(store[PreferenceKeys.ocrLanguages] == OCRLanguages.defaults.joined(separator: ","), "New domain has three default languages")
check(store[PreferenceKeys.hasOfferedLaunchAtLogin], "Migration preserves consent")
defaults.removeObject(forKey: "ocrLanguages")
defaults.set(true, forKey: "finnishTextMode")
store.migrate()
check(store[PreferenceKeys.ocrLanguages] == "fi-FI", "Retired Finnish-only setting migrates")
check(defaults.object(forKey: "finnishTextMode") == nil, "Retired switch removed")
store[PreferenceKeys.ocrLanguages] = "ko-KR,en-US,fa-IR,ja-JP,fr-FR"
defaults.set(true, forKey: "finnishTextMode")
store.migrate()
check(store[PreferenceKeys.ocrLanguages] == "ko-KR,en-US,fa-IR,ja-JP,fr-FR", "Modern selection takes precedence")
let snapshot = defaults.dictionaryRepresentation()
store.migrate()
check(NSDictionary(dictionary: snapshot).isEqual(to: defaults.dictionaryRepresentation()), "Migration is idempotent")
let isolated = BakerPreferences(defaults: UserDefaults(suiteName: suite + ".other")!)
check(isolated[PreferenceKeys.copyCapturedImages], "Independent preference domain retains default")
isolated.defaults.removePersistentDomain(forName: suite + ".other")
let valid = SettingsPreset(copyImages: false, copyText: true, openTextEditor: false, captureSounds: true,
    hideDesktopIcons: true, visibleCaptures: 4, formulaHistoryLimit: 100, formulaHistoryDays: 90,
    mathFont: MathFont.latinModern.rawValue, languages: ["ko-KR","en-US","fa-IR","ja-JP","fr-FR"], formulaFormat: "LaTeX", latexStyle: LatexCopyStyle.bare.rawValue)
try valid.validate()
let data = try JSONEncoder().encode(valid)
let decoded = try JSONDecoder().decode(SettingsPreset.self, from: data)
check(decoded == valid, "Portable preset round trip")
let fields = try JSONSerialization.jsonObject(with: data) as! [String: Any]
var weekFields = fields; weekFields["formulaHistoryDays"] = 7
let weekPreset = try JSONDecoder().decode(SettingsPreset.self, from: JSONSerialization.data(withJSONObject: weekFields))
try weekPreset.validate()
check(weekPreset.formulaHistoryDays == 7, "Seven-day formula retention survives preset round trip")
for local in ["storageDirectory","formulaPython","formulaConfig","captureShortcuts","bakerMenuLayout","hasOfferedLaunchAtLogin","repeatCaptureArea"] {
    check(fields[local] == nil, "Preset excludes local setting: " + local)
}
var bad = fields; bad["languages"] = ["ko-KR","en-US","de-DE","ja-JP","fa-IR","ar-SA"]
let badPreset = try JSONDecoder().decode(SettingsPreset.self, from: JSONSerialization.data(withJSONObject: bad))
do { try badPreset.validate(); check(false, "Six-language preset must fail") }
catch let failure as BakerError { check(failure.code == .invalidInput, "Preset reports typed input failure") }
for (error,expected) in [
    (NSError(domain:NSURLErrorDomain,code:NSURLErrorTimedOut), BakerError.Code.downloadFailed),
    (NSError(domain:NSURLErrorDomain,code:NSURLErrorCancelled), .cancelled),
    (NSError(domain:NSCocoaErrorDomain,code:NSFileReadNoPermissionError), .fileAccessDenied),
    (NSError(domain:NSCocoaErrorDomain,code:NSFileWriteOutOfSpaceError), .insufficientSpace),
    (NSError(domain:NSCocoaErrorDomain,code:NSFileReadNoSuchFileError), .storageFailed),
    (NSError(domain:NSCocoaErrorDomain,code:NSUserCancelledError), .cancelled),
    (NSError(domain:NSPOSIXErrorDomain,code:Int(POSIXErrorCode.ENOSPC.rawValue)), .insufficientSpace)
] {
    check(BakerError.wrapping(error).code == expected, "System error classified by domain/code")
}
check(BakerError.wrapping(CancellationError()).code == .cancelled, "Task cancellation remains cancellation")
check(BakerError.wrapping(NSError(domain:"Unknown",code:7),fallback:.recordingFailed).code == .recordingFailed, "Unknown errors retain explicit operation context")
let original = BakerError(message:"Missing engine",code:.modelNotReady,diagnostic:"cause",recovery:.pdfSettings)
let preserved = BakerError.wrapping(original,fallback:.downloadFailed)
check(preserved.code == .modelNotReady && preserved.recovery == .pdfSettings && preserved.diagnostic == "cause", "Wrapping retains original type, recovery and diagnostic")
check(original.userDescription == "Missing engine", "Technical diagnostic excluded from normal UI")
check(original.recoverySuggestion?.contains("Settings → Advanced → Offline Model") == true, "PDF recovery destination retained")
for code in BakerError.Code.allCases {
    let failure = BakerError(message:"Example",code:code)
    check(failure.recoverySuggestion != nil || [.cancelled,.operationFailed,.previewUnsupported].contains(code), "Each operational error has recovery guidance")
}
check(BakerError(message:"timeout",code:.processTimedOut).isRetryable, "Transient timeout is retryable")
check(!BakerError(message:"bad hash",code:.integrityFailed).isRetryable, "Corrupt models are not blindly retried")
check(!BakerError(message:"permission",code:.permissionDenied).isRetryable, "Permissions require user action")
check(!BakerError(message:"cancel",code:.cancelled).isRetryable, "Cancellation never retries")
var appearance = AppStorage(PreferenceKeys.appearance, store: defaults)
appearance.wrappedValue = "dark"
check(store[PreferenceKeys.appearance] == "dark", "UI binding writes supplied preference domain")
var copyImages = AppStorage(PreferenceKeys.copyCapturedImages, store: defaults)
copyImages.wrappedValue = true
check(store[PreferenceKeys.copyCapturedImages], "Boolean UI binding uses the same store")
check(BakerError.Recovery.pdfSettings.settingsPage == .advanced, "PDF recovery opens Advanced category")
check(BakerError.Recovery.formulaSettings.settingsPage == .formula, "Formula recovery opens Formula category")
check(BakerError.Recovery.captureSettings.settingsPage == .capture, "Language recovery opens Capture category")
check(BakerError.Recovery.chooseLocation.settingsPage == .storage, "Storage recovery opens Storage category")
check(BakerError.Recovery.retry.settingsPage == nil, "Retry cannot unexpectedly open Settings")
let reporter = ErrorHarness()
reporter.report(original)
check(reporter.failure?.code == .modelNotReady && reporter.problem == "Missing engine", "Reporter retains typed failure")
reporter.report(CancellationError())
check(reporter.problem == "Missing engine", "Cancelled work does not replace an existing problem")
reporter.problem = nil
check(reporter.failure == nil, "Dismissing a problem clears its stale recovery")
reporter.report(original, context: "PDF conversion:")
check(reporter.problem == "PDF conversion: Missing engine" && reporter.failure?.recovery == .pdfSettings, "Context preserves recovery destination")
reporter.problem = "Independent message"
check(reporter.failure == nil, "Plain replacement cannot inherit unrelated recovery")
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let fixture = output.appendingPathComponent("integrity-fixture.bin")
try Data("Baker".utf8).write(to: fixture)
do { try ModelIntegrity.verify(fixture, bytes: 6, sha256: ""); check(false, "Wrong model size accepted") }
catch let failure as BakerError { check(failure.code == .integrityFailed, "Model size rejection has typed cause") }
do { try ModelIntegrity.verify(fixture, bytes: 5, sha256: String(repeating: "0", count: 64)); check(false, "Wrong model hash accepted") }
catch let failure as BakerError { check(failure.code == .integrityFailed, "Model hash rejection has typed cause") }
do {
    try InstallerHarness.unpack(python: URL(fileURLWithPath: "/usr/bin/false"), installer: fixture, descriptor: fixture, archive: fixture, stage: output)
    check(false, "Failed installer accepted")
} catch let failure as BakerError {
    check(failure.code == .integrityFailed && failure.recovery == .pdfSettings, "Installer preserves verification failure and PDF destination")
}
try InstallerHarness.unpack(python: URL(fileURLWithPath: "/usr/bin/true"), installer: fixture, descriptor: fixture, archive: fixture, stage: output)
check(true, "Successful process result accepted without an actual installation")
reporter.shuttingDown = true
reporter.problem = nil
reporter.report(original)
check(reporter.problem == nil, "Shutdown suppresses late failure presentation")
print("Preferences and errors: \(checks) checks passed")
