import Foundation
import BakerCore

/// The persisted names remain stable across releases; types and defaults live here.
struct PreferenceKey<Value> {
    let name: String
    let defaultValue: Value
    init(_ name: String, _ defaultValue: Value) { self.name = name; self.defaultValue = defaultValue }
}

enum PreferenceKeys {
    static let appearance = PreferenceKey("appearance", "system")
    static let developerRuntimeOverrides = PreferenceKey("developerRuntimeOverrides", false)
    static let python = PreferenceKey("formulaPython", "")
    static let config = PreferenceKey("formulaConfig", "")
    static let copyCapturedImages = PreferenceKey("copyCapturedImages", true)
    static let copyRecognisedText = PreferenceKey("copyRecognisedText", true)
    static let showResults = PreferenceKey("showResults", false)
    static let tesseractExecutable = PreferenceKey("tesseractExecutable", "")
    static let ocrLanguages = PreferenceKey("ocrLanguages", OCRLanguages.defaults.joined(separator: ","))
    static let hideDesktopIcons = PreferenceKey("hideDesktopIcons", false)
    static let captureSounds = PreferenceKey("captureSounds", true)
    static let mathFont = PreferenceKey("mathFont", "Latin Modern Math")
    static let visibleCaptures = PreferenceKey("visibleCaptures", 3)
    static let imageHistoryLimit = PreferenceKey("imageHistoryLimit", 0)
    static let imageHistoryDays = PreferenceKey("imageHistoryDays", 0)
    static let imageHistoryApprovedDirectory = PreferenceKey("imageHistoryApprovedDirectory", "")
    static let formulaHistoryLimit = PreferenceKey("formulaHistoryLimit", 50)
    static let formulaHistoryDays = PreferenceKey("formulaHistoryDays", 0)
    static let formulaOutputFormat = PreferenceKey("formulaOutputFormat", "LaTeX")
    static let formulaLatexStyle = PreferenceKey("formulaLatexStyle", "")
    static let storageDirectory = PreferenceKey("storageDirectory", "")
    static let recordingFormat = PreferenceKey("recordingFormat", "video")
    static let captureShortcuts = PreferenceKey("captureShortcuts", Data())
    static let menuLayout = PreferenceKey("bakerMenuLayout", Data())
    static let repeatCaptureArea = PreferenceKey("repeatCaptureArea", Data())
    static let hasShownRecognitionSetup = PreferenceKey("hasShownRecognitionSetup", false)
    static let hasOfferedLaunchAtLogin = PreferenceKey("hasOfferedLaunchAtLogin", false)
    static let retiredCloudCredentialsRemoved = PreferenceKey("retiredCloudCredentialsRemoved", false)
    enum Legacy {
        static let finnishTextMode = "finnishTextMode"
        static let cloud = ["googleDriveClientID", "googleDriveImports", "dropboxAppKey", "dropboxImports"]
    }
}

/// An inexpensive value wrapper around an explicitly supplied preference domain.
/// Paths, login consent and model files never travel in portable presets.
struct BakerPreferences {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    subscript<Value>(_ key: PreferenceKey<Value>) -> Value {
        get { defaults.object(forKey: key.name) as? Value ?? key.defaultValue }
        nonmutating set { defaults.set(newValue, forKey: key.name) }
    }
    var captureDirectory: URL? {
        let path = self[PreferenceKeys.storageDirectory]
        return path.hasPrefix("/") ? URL(fileURLWithPath: path, isDirectory: true) : nil
    }
    /// Idempotent: a modern selection takes precedence over the retired switch.
    func migrate() {
        let key = PreferenceKeys.ocrLanguages
        let old = PreferenceKeys.Legacy.finnishTextMode
        let existing = defaults.string(forKey: key.name)
        let languages = existing?.split(separator: ",").map(String.init)
            ?? (defaults.bool(forKey: old) ? ["fi-FI"] : OCRLanguages.defaults)
        self[key] = OCRLanguages.normalized(languages).joined(separator: ",")
        defaults.removeObject(forKey: old)
    }
}
