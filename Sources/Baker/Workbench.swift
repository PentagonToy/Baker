import BakerCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class Workbench: ObservableObject {
    @Published var imageURL: URL?
    @Published var image: NSImage?
    @Published var text = ""
    @Published var latex = ""
    @Published var unicode = ""
    @Published var unicodeMessage = ""
    @Published var format: OutputFormat = .text
    @Published var busy = false {
        didSet { if !busy, historyNeedsMaintenance, !shuttingDown { Task { [weak self] in self?.refreshCaptureHistory(enforceLimits: true) } } }
    }
    var historyNeedsMaintenance = false
    @Published var status = "Open an image or capture a screen region."
    @Published var problem: String? {
        didSet { if problem != failure?.userDescription { failure = nil } }
    }
    @Published private(set) var failure: BakerError?
    func report(_ error: Error, fallback: BakerError.Code = .operationFailed, context: String? = nil) {
        guard !shuttingDown else { return }
        let cause = BakerError.wrapping(error, fallback: fallback)
        guard cause.code != .cancelled else { return }
        let value = context.map { BakerError(message: $0 + " " + cause.userDescription, code: cause.code, diagnostic: cause.diagnostic, recovery: cause.recovery) } ?? cause
        failure = value; problem = value.userDescription
    }
    @Published var exportURL: URL?
    @Published var exportSummary = ""
    @Published var previousArea: RepeatCaptureArea?
    var canRepeatArea: Bool { previousArea?.resolve() != nil }
    @Published var isRecording = false
    @Published var isConvertingPDF = false
    @Published var documentProgress = DocumentProgress()
    let screenRecordingPermission = ScreenRecordingPermission()
    var onReopen: (() -> Void)?
    let launchAtLogin: LaunchAtLogin
    let formulaSetup = FormulaSetup()
    let pdfEngineSetup = PDFEngineSetup()
    var onFormulaSetupNeeded: (() -> Void)?
    var onSettingsNeeded: ((SettingsPage) -> Void)?
    @AppStorage(PreferenceKeys.developerRuntimeOverrides) var developerRuntimeOverrides
    @AppStorage(PreferenceKeys.python) var python
    @AppStorage(PreferenceKeys.config) var config
    @AppStorage(PreferenceKeys.copyCapturedImages) var copyCapturedImages
    @AppStorage(PreferenceKeys.copyRecognisedText) var copyRecognisedText
    @AppStorage(PreferenceKeys.showResults) var showResults
    var finnishTextMode: Bool { selectedOCRLanguages.contains("fi-FI") }
    var textEngineExecutable: String { developerRuntimeOverrides && !tesseractExecutable.isEmpty ? tesseractExecutable : TesseractOCR.defaultExecutable }
    @AppStorage(PreferenceKeys.tesseractExecutable) var tesseractExecutable
    @Published var ocrLanguageSelection = PreferenceKeys.ocrLanguages.defaultValue {
        didSet { preferences[PreferenceKeys.ocrLanguages] = ocrLanguageSelection }
    }
    var selectedOCRLanguages: [String] { OCRLanguages.normalized(ocrLanguageSelection.split(separator: ",").map(String.init)) }
    func setOCRLanguage(_ code: String, enabled: Bool) {
        ocrLanguageSelection = OCRLanguages.setting(code, enabled: enabled, in: selectedOCRLanguages).joined(separator: ",")
    }
    @AppStorage(PreferenceKeys.hideDesktopIcons) var hideDesktopIcons
    @AppStorage(PreferenceKeys.captureSounds) var captureSounds
    let feedback = CaptureFeedback()
    @Published var mathFont = PreferenceKeys.mathFont.defaultValue {
        didSet { preferences[PreferenceKeys.mathFont] = mathFont }
    }
    @Published var captures: [CaptureRecord] = []
    @Published var recordings: [RecordingRecord] = []
    @Published var historyRevision = 0
    @Published var imageHistoryLimit = 0
    @Published var imageHistoryDays = 0
    var historyRefreshTask: Task<Void, Never>?

    @Published var visibleCaptures = PreferenceKeys.visibleCaptures.defaultValue {
        didSet { preferences[PreferenceKeys.visibleCaptures] = visibleCaptures }
    }
    let library: CaptureLibrary
    var captureStore: CaptureStore { library.store }
    @Published var storageDirectory: URL
    var switchingStorage = false
    var applyingPreset = false
    var canChangeStorage: (() -> Bool)?
    var onStorageChanged: (() -> Void)?
    var initialLoadTask: Task<Void, Never>?
    var importTask: Task<Void, Never>?
    @Published var activeCaptureID: UUID?
    @Published var formulaInputPending = false
    @Published var focusedFormulaID: UUID?
    var formulaCapturePending = false
    @Published var savedFormulas: [UUID: SavedFormula] = [:]
    @Published var formulaHistoryLimit = PreferenceKeys.formulaHistoryLimit.defaultValue {
        didSet { preferences[PreferenceKeys.formulaHistoryLimit] = formulaHistoryLimit; applyFormulaRetention() }
    }
    @Published var formulaHistoryDays = PreferenceKeys.formulaHistoryDays.defaultValue {
        didSet { preferences[PreferenceKeys.formulaHistoryDays] = formulaHistoryDays; applyFormulaRetention() }
    }
    @Published var formulaResults: [UUID: FormulaResult] = [:]
    var onFormulaReady: ((UUID) -> Void)?
    var onEditResult: (() -> Void)?
    let clipboardFlow: ClipboardCoordinator
    let preferences: BakerPreferences
    var preferredFormulaFormat: OutputFormat {
        let value = OutputFormat(rawValue: preferences[PreferenceKeys.formulaOutputFormat]) ?? .latex
        return value == .text ? .latex : value
    }
    var preferredLatexStyle: LatexCopyStyle {
        LatexCopyStyle(rawValue: preferences[PreferenceKeys.formulaLatexStyle]) ?? .bare
    }
    var onImageReady: (() -> Void)?
    var onCaptureVisibility: ((Bool) -> Void)?

    init(captureDirectory: URL? = nil, clipboard: NSPasteboard = .general, defaults: UserDefaults = .standard) {
        clipboardFlow = ClipboardCoordinator(pasteboard: clipboard)
        let preferences = BakerPreferences(defaults: defaults)
        preferences.migrate()
        self.preferences = preferences
        launchAtLogin = LaunchAtLogin(defaults: defaults)
        captureFlow = CaptureCoordinator(preferences: preferences)
        previousArea = RepeatCaptureArea.load(defaults: defaults)
        _developerRuntimeOverrides = AppStorage(PreferenceKeys.developerRuntimeOverrides, store: defaults)
        _python = AppStorage(PreferenceKeys.python, store: defaults)
        _config = AppStorage(PreferenceKeys.config, store: defaults)
        _copyCapturedImages = AppStorage(PreferenceKeys.copyCapturedImages, store: defaults)
        _copyRecognisedText = AppStorage(PreferenceKeys.copyRecognisedText, store: defaults)
        _showResults = AppStorage(PreferenceKeys.showResults, store: defaults)
        _captureSounds = AppStorage(PreferenceKeys.captureSounds, store: defaults)
        _hideDesktopIcons = AppStorage(PreferenceKeys.hideDesktopIcons, store: defaults)
        let configured = preferences.captureDirectory
        let directory = (captureDirectory ?? configured ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Baker", isDirectory: true)).standardizedFileURL.resolvingSymlinksInPath()
        storageDirectory = directory
        var locationError: BakerError?
        if captureDirectory == nil && configured == nil {
            do { _ = try CaptureLocation.prepare(documents: directory.deletingLastPathComponent(), pictures: FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!) }
            catch { locationError = BakerError.wrapping(error, fallback: .storageFailed) }
        }
        library = CaptureLibrary(directory: directory)
        imageHistoryLimit = [0, 50, 100, 250, 500, 1000, 5000].contains(preferences[PreferenceKeys.imageHistoryLimit]) ? preferences[PreferenceKeys.imageHistoryLimit] : 0
        imageHistoryDays = [0, 7, 10, 30, 90].contains(preferences[PreferenceKeys.imageHistoryDays]) ? preferences[PreferenceKeys.imageHistoryDays] : 0
        mathFont = preferences[PreferenceKeys.mathFont]
        visibleCaptures = max(1, min(5, preferences[PreferenceKeys.visibleCaptures]))
        formulaHistoryLimit = max(1, min(500, preferences[PreferenceKeys.formulaHistoryLimit]))
        formulaHistoryDays = [0, 10, 30].contains(preferences[PreferenceKeys.formulaHistoryDays]) ? preferences[PreferenceKeys.formulaHistoryDays] : 0
        _tesseractExecutable = AppStorage(PreferenceKeys.tesseractExecutable, store: defaults)
        ocrLanguageSelection = preferences[PreferenceKeys.ocrLanguages]
        let initialStore = captureStore
        initialLoadTask = Task {
            defer { initialLoadTask = nil; if !shuttingDown { refreshCaptureHistory(enforceLimits: true) } }
            if let locationError { report(locationError) }
            do {
                let records = try await initialStore.reconcileHistory()
                let formulas = try await initialStore.savedFormulas()
                guard !shuttingDown, captureStore === initialStore else { return }
                if captures.isEmpty { captures = records }
                savedFormulas = formulas
                do {
                    let recorded = try await initialStore.recordings()
                    if !shuttingDown, captureStore === initialStore { recordings = recorded }
                }
                catch { report(error, fallback: .storageFailed, context: "Recording history could not be opened:") }
                do {
                    let values = try await initialStore.maintainFormulas(limit: formulaHistoryLimit, days: formulaHistoryDays)
                    if captureStore === initialStore { savedFormulas = values }
                }
                catch { report(error, fallback: .storageFailed, context: "Formula history could not be opened:") }
            }
            catch { report(error, fallback: .storageFailed, context: "Capture history could not be opened:") }
        }
    }

    var onResultReady: (() -> Void)?
    var onExportReady: (() -> Void)?
    let captureFlow: CaptureCoordinator
    let recognitionFlow = RecognitionCoordinator()
    let documentFlow = DocumentCoordinator()
    let fileExports = FileExportCoordinator()
    var ownedExportDirectory: URL?
    var pendingDocumentDirectory: URL?
    func flushFormulaHistory() async { await library.flushHistory() }
    lazy var filesInbox = FilesInbox(model: self)
    var onOpenFiles: ((PDFExportFormat?) -> Void)?
    var shuttingDown = false
    var pinWindows: [NSWindow] = []
    var selectedMathFont: MathFont { MathFont(rawValue: mathFont) ?? .latinModern }

    func shutdown() async {
        formulaSetup.cancel(); pdfEngineSetup.cancel(); shuttingDown = true
        await filesInbox.close(); await pdfEngineSetup.close()
        library.cancelThumbnails(); clipboardFlow.invalidate(); initialLoadTask?.cancel(); importTask?.cancel(); historyRefreshTask?.cancel()
        await captureFlow.close(); await recognitionFlow.close(); await documentFlow.close(); await fileExports.close()
        _ = await initialLoadTask?.result; _ = await importTask?.result; _ = await historyRefreshTask?.result
        await library.flushHistory()
        cleanup()
    }
    func cleanup() {
        initialLoadTask?.cancel()
        captureFlow.cancel(); recognitionFlow.cancel(); documentFlow.cancel(); fileExports.cancel()
        if let ownedExportDirectory { try? FileManager.default.removeItem(at: ownedExportDirectory) }
        if let pendingDocumentDirectory { try? FileManager.default.removeItem(at: pendingDocumentDirectory) }
    }
}
