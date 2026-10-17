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
    @Published var busy = false
    @Published var status = "Open an image or capture a screen region."
    @Published var problem: String?
    @Published var exportURL: URL?
    @Published var exportSummary = ""
    @Published var isRecording = false
    @Published var isConvertingPDF = false
    @Published var documentProgress = DocumentProgress()
    let formulaSetup = FormulaSetup()
    let pdfEngineSetup = PDFEngineSetup()
    var onFormulaSetupNeeded: (() -> Void)?
    @AppStorage("developerRuntimeOverrides") var developerRuntimeOverrides = false
    @AppStorage("formulaPython") var python = ""
    @AppStorage("formulaConfig") var config = ""
    @AppStorage("copyCapturedImages") var copyCapturedImages = true
    @AppStorage("copyRecognisedText") var copyRecognisedText = true
    @AppStorage("showResults") var showResults = false
    var finnishTextMode: Bool { selectedOCRLanguages.contains("fi-FI") }
    var textEngineExecutable: String { developerRuntimeOverrides ? tesseractExecutable : FinnishOCR.defaultExecutable }
    @AppStorage("tesseractExecutable") var tesseractExecutable = FinnishOCR.defaultExecutable
    @Published private(set) var ocrLanguageSelection = OCRLanguages.defaults.joined(separator: ",") {
        didSet { formulaPreferences.set(ocrLanguageSelection, forKey: "ocrLanguages") }
    }
    var selectedOCRLanguages: [String] { OCRLanguages.normalized(ocrLanguageSelection.split(separator: ",").map(String.init)) }
    func setOCRLanguage(_ code: String, enabled: Bool) {
        ocrLanguageSelection = OCRLanguages.setting(code, enabled: enabled, in: selectedOCRLanguages).joined(separator: ",")
    }
    @AppStorage("hideDesktopIcons") var hideDesktopIcons = false
    @AppStorage("captureSounds") var captureSounds = true
    private let feedback = CaptureFeedback()
    @Published var mathFont = UserDefaults.standard.string(forKey: "mathFont") ?? MathFont.latinModern.rawValue {
        didSet { formulaPreferences.set(mathFont, forKey: "mathFont") }
    }
    @Published var captures: [CaptureRecord] = []
    @Published var visibleCaptures = UserDefaults.standard.object(forKey: "visibleCaptures") as? Int ?? 3 {
        didSet { formulaPreferences.set(visibleCaptures, forKey: "visibleCaptures") }
    }
    private var captureStore: CaptureStore
    @Published private(set) var storageDirectory: URL
    private var switchingStorage = false
    private var applyingPreset = false
    var canChangeStorage: (() -> Bool)?
    var onStorageChanged: (() -> Void)?
    private var thumbnailCache: [UUID: NSImage] = [:]
    private var importTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var clipboardRequest = 0
    @Published var activeCaptureID: UUID?
    @Published var formulaInputPending = false
    @Published var focusedFormulaID: UUID?
    private(set) var formulaCapturePending = false
    @Published var savedFormulas: [UUID: SavedFormula] = [:]
    @Published var formulaHistoryLimit = 50 {
        didSet { formulaPreferences.set(formulaHistoryLimit, forKey: "formulaHistoryLimit"); applyFormulaRetention() }
    }
    @Published var formulaHistoryDays = 0 {
        didSet { formulaPreferences.set(formulaHistoryDays, forKey: "formulaHistoryDays"); applyFormulaRetention() }
    }
    private var formulaSaveTask: Task<Void, Never>?
    @Published var formulaResults: [UUID: FormulaResult] = [:]
    var onFormulaReady: ((UUID) -> Void)?
    var onEditResult: (() -> Void)?
    private var formulaRenderTask: Task<NSImage, Error>?
    private let clipboard: NSPasteboard
    private let formulaPreferences: UserDefaults
    private var preferredFormulaFormat: OutputFormat {
        let value = OutputFormat(rawValue: formulaPreferences.string(forKey: "formulaOutputFormat") ?? "LaTeX") ?? .latex
        return value == .text ? .latex : value
    }
    private var preferredLatexStyle: LatexCopyStyle {
        LatexCopyStyle(rawValue: formulaPreferences.string(forKey: "formulaLatexStyle") ?? "") ?? .bare
    }
    var onImageReady: (() -> Void)?
    var onCaptureVisibility: ((Bool) -> Void)?

    init(captureDirectory: URL? = nil, clipboard: NSPasteboard = .general, formulaPreferences: UserDefaults = .standard) {
        self.clipboard = clipboard
        self.formulaPreferences = formulaPreferences
        _developerRuntimeOverrides = AppStorage(wrappedValue: false, "developerRuntimeOverrides", store: formulaPreferences)
        _python = AppStorage(wrappedValue: "", "formulaPython", store: formulaPreferences)
        _config = AppStorage(wrappedValue: "", "formulaConfig", store: formulaPreferences)
        _copyCapturedImages = AppStorage(wrappedValue: true, "copyCapturedImages", store: formulaPreferences)
        _copyRecognisedText = AppStorage(wrappedValue: true, "copyRecognisedText", store: formulaPreferences)
        _showResults = AppStorage(wrappedValue: false, "showResults", store: formulaPreferences)
        _captureSounds = AppStorage(wrappedValue: true, "captureSounds", store: formulaPreferences)
        _hideDesktopIcons = AppStorage(wrappedValue: false, "hideDesktopIcons", store: formulaPreferences)
        let configured = formulaPreferences.string(forKey: "storageDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) }
        let directory = (captureDirectory ?? configured ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Baker", isDirectory: true)).standardizedFileURL.resolvingSymlinksInPath()
        storageDirectory = directory
        var locationError: String?
        if captureDirectory == nil && configured == nil {
            do { _ = try CaptureLocation.prepare(documents: directory.deletingLastPathComponent(), pictures: FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!) }
            catch { locationError = "Could not move the previous captures to Documents: \(error.localizedDescription)" }
        }
        captureStore = CaptureStore(directory: directory)
        mathFont = formulaPreferences.string(forKey: "mathFont") ?? MathFont.latinModern.rawValue
        visibleCaptures = max(1, min(5, formulaPreferences.object(forKey: "visibleCaptures") as? Int ?? 3))
        formulaHistoryLimit = max(1, min(500, formulaPreferences.object(forKey: "formulaHistoryLimit") as? Int ?? 50))
        formulaHistoryDays = [0, 10, 30].contains(formulaPreferences.integer(forKey: "formulaHistoryDays")) ? formulaPreferences.integer(forKey: "formulaHistoryDays") : 0
        _tesseractExecutable = AppStorage(wrappedValue: FinnishOCR.defaultExecutable, "tesseractExecutable", store: formulaPreferences)
        let previousLanguages = formulaPreferences.string(forKey: "ocrLanguages")?.split(separator: ",").map(String.init) ?? OCRLanguages.defaults
        let migrated = formulaPreferences.bool(forKey: "finnishTextMode") ? ["fi-FI"] : previousLanguages
        ocrLanguageSelection = OCRLanguages.normalized(migrated).joined(separator: ",")
        formulaPreferences.set(ocrLanguageSelection, forKey: "ocrLanguages")
        formulaPreferences.removeObject(forKey: "finnishTextMode")
        let initialStore = captureStore
        Task {
            if let locationError { problem = locationError }
            do {
                let records = try await initialStore.records()
                let formulas = try await initialStore.savedFormulas()
                guard captureStore === initialStore else { return }
                if captures.isEmpty { captures = records }
                savedFormulas = formulas
                do {
                    let values = try await initialStore.maintainFormulas(limit: formulaHistoryLimit, days: formulaHistoryDays)
                    if captureStore === initialStore { savedFormulas = values }
                }
                catch { problem = "Formula history could not be opened: \(error.localizedDescription)" }
            }
            catch { problem = "Capture history could not be opened: \(error.localizedDescription)" }
        }
    }
    func captureURL(_ record: CaptureRecord) -> URL { captureStore.directory.appendingPathComponent(record.fileName) }
    func originalImage(_ record: CaptureRecord) async throws -> NSImage {
        let store = captureStore
        let raster = try await store.original(record)
        guard captureStore === store, !Task.isCancelled else { throw CancellationError() }
        return NSImage(cgImage: raster, size: .zero)
    }
    func cachedThumbnail(_ id: UUID) -> NSImage? { thumbnailCache[id] }
    func thumbnail(_ record: CaptureRecord) async throws -> NSImage {
        if let cached = thumbnailCache[record.id] { return cached }
        let store = captureStore
        let image = NSImage(cgImage: try await store.thumbnail(record), size: .zero)
        guard captureStore === store else { throw CancellationError() }
        // Another request may have filled the cache while disk work was in flight.
        if let cached = thumbnailCache[record.id] { return cached }
        if thumbnailCache.count >= 6, let victim = thumbnailCache.keys.first(where: { $0 != activeCaptureID && $0 != focusedFormulaID }) {
            thumbnailCache.removeValue(forKey: victim)
        }
        thumbnailCache[record.id] = image
        return image
    }
    func searchCaptures(_ query: String) async throws -> Set<UUID> { try await captureStore.search(query) }
    func revealCaptures() { NSWorkspace.shared.open(captureStore.directory) }
    func copyCapture(_ record: CaptureRecord) async -> Bool { await copyImageFile(captureURL(record)) }
    private func copyImageFile(_ url: URL) async -> Bool {
        clipboardRequest += 1
        let request = clipboardRequest, previousClipboard = clipboard.changeCount
        do {
            let payload = try await Task.detached(priority: .userInitiated) { try ImageClipboard.prepare(imageURL: url) }.value
            guard !shuttingDown, !Task.isCancelled, request == clipboardRequest else { return false }
            guard clipboard.changeCount == previousClipboard else { status = "Clipboard changed. Copy again to replace it."; return false }
            try ImageClipboard.write(payload, to: clipboard)
            status = "Image copied."
            return true
        } catch { problem = error.localizedDescription; return false }
    }
    func confirmCaptureSaved(_ record: CaptureRecord) async -> Bool {
        do {
            _ = try await captureStore.thumbnail(record)
            status = "Saved to \(captureURL(record).deletingLastPathComponent().path)."
            return true
        } catch { problem = error.localizedDescription; return false }
    }
    func saveCapture(_ record: CaptureRecord) { saveImageFile(captureURL(record)) }
    func selectCapture(_ record: CaptureRecord, action: CaptureAction) {
        guard !busy else { return }
        if (action == .formula || action == .unicode), savedFormulas[record.id] != nil {
            openSavedFormula(record.id); return
        }
        let url = captureURL(record)
        guard let selected = NSImage(contentsOf: url) else { problem = "The saved image could not be opened."; return }
        if case .image = action { pinImage(selected); return }
        imageURL = url; image = selected; activeCaptureID = record.id
        text = ""; latex = ""; unicode = ""; unicodeMessage = ""
        switch action {
        case .image: break
        case .text: recognise(formula: false)
        case .formula: recognise(formula: true, outputFormat: preferredFormulaFormat)
        case .unicode: recognise(formula: true, outputFormat: .unicode)
        }
    }
    var onResultReady: (() -> Void)?
    var onExportReady: (() -> Void)?
    private var ownedImage: URL?
    private let captureService = CaptureService()
    private var scrollSession: ScrollCaptureSession?
    private var recordingSession: RecordingSession?
    private var recognitionTask: Task<FormulaRecognition, Error>?
    private var recognitionJob: Task<Void, Never>?
    private var formulaEditJob: Task<Void, Never>?
    private var documentTask: Task<PDFConversionReport, Error>?
    private var ownedExportDirectory: URL?
    private var pendingDocumentDirectory: URL?
    func flushFormulaHistory() async { _ = await formulaSaveTask?.value }
    lazy var filesInbox = FilesInbox(model: self)
    var onOpenFiles: ((PDFExportFormat?) -> Void)?
    private var shuttingDown = false
    private var pinWindows: [NSWindow] = []
    var selectedMathFont: MathFont { MathFont(rawValue: mathFont) ?? .latinModern }

    var output: String {
        switch format { case .text: return text; case .latex: return (activeCaptureID.flatMap { formulaResults[$0]?.style } ?? preferredLatexStyle).format(latex); case .markdown: return LatexCopyStyle.displayDollar.format(latex); case .unicode: return unicode; case .keynote: return LatexWhitespace.compact(KeynoteLatex.convert(latex).text) }
    }

    func openImage(asFormula: Bool = false) {
        guard !busy, !shuttingDown else { return }
        if !asFormula, let onOpenFiles { onOpenFiles(nil); return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .bmp]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            formulaCapturePending = asFormula
            startImport(asFormula: asFormula) { try await self.accept(try await self.captureStore.add(file: url)) }
        }
    }
    func importFormulaImage(_ url: URL) {
        guard !busy, !shuttingDown, url.isFileURL else { return }
        formulaCapturePending = true
        startImport(asFormula: true) { try await self.accept(try await self.captureStore.add(file: url)) }
    }
    private func startImport(asFormula: Bool = false, _ operation: @escaping @MainActor () async throws -> Void) {
        busy = true; status = "Saving capture…"
        importTask = Task {
            defer { importTask = nil; formulaCapturePending = false }
            do {
                try await operation()
                busy = false
                if asFormula { recognise(formula: true, outputFormat: preferredFormulaFormat) }
            } catch {
                busy = false
                if error is CancellationError { status = "Capture processing cancelled." }
                else if !shuttingDown { problem = error.localizedDescription }
            }
        }
    }
    private func accept(_ stored: StoredCapture, notify: Bool = true) async throws {
        try Task.checkCancellation()
        guard !shuttingDown else { throw CancellationError() }
        let url = captureURL(stored.record)
        guard let loaded = NSImage(contentsOf: url) else { throw BakerError(message: "The saved capture could not be opened.") }
        let records = try await captureStore.records()
        try Task.checkCancellation()
        guard !shuttingDown else { throw CancellationError() }
        captures = records
        thumbnailCache = thumbnailCache.filter { id, _ in captures.prefix(5).contains { $0.id == id } }
        thumbnailCache[stored.record.id] = NSImage(cgImage: stored.thumbnail, size: .zero)
        imageURL = url; image = loaded; activeCaptureID = stored.record.id
        text = ""; latex = ""; unicode = ""; unicodeMessage = ""; format = .text
        status = "Capture saved."
        if notify { onImageReady?() }
    }
    func saveEditedCapture(_ image: CGImage, replacing record: CaptureRecord) async throws -> CaptureRecord {
        guard !busy, !shuttingDown else { throw BakerError(message: "Wait for the current operation before saving edits.") }
        busy = true; defer { busy = false }
        await flushFormulaHistory()
        let stored = try await captureStore.replace(image: image, record: record)
        savedFormulas.removeValue(forKey: record.id); formulaResults.removeValue(forKey: record.id)
        if focusedFormulaID == record.id { focusedFormulaID = nil }
        try await accept(stored, notify: false)
        if copyCapturedImages { _ = await copyCapture(stored.record) }
        status = "Capture overwritten. Previous OCR result removed."
        return stored.record
    }
    private func adoptFormulas(_ values: [UUID: SavedFormula]) {
        savedFormulas = values
        formulaResults = formulaResults.filter { values[$0.key] != nil || $0.value.phase == .recognising }
        if let id = focusedFormulaID, values[id] == nil { focusedFormulaID = nil }
    }
    func applyFormulaRetention() {
        guard !shuttingDown, !switchingStorage, !applyingPreset else { return }
        let previous = formulaSaveTask, limit = formulaHistoryLimit, days = formulaHistoryDays
        formulaSaveTask = Task {
            _ = await previous?.value
            do { adoptFormulas(try await captureStore.maintainFormulas(limit: limit, days: days)) }
            catch { problem = "Formula retention could not be updated: \(error.localizedDescription)" }
        }
    }
    func clearPreviewCache() {
        guard !busy else { return }
        FormulaPreviewRenderer.shared.clearCache()
        thumbnailCache = [:]; formulaResults = [:]; focusedFormulaID = nil; image = nil
        status = "Cached previews cleared. Saved files and formula history remain."
    }
    func clearFormulaHistory() {
        guard !busy else { return }
        let previous = formulaSaveTask
        formulaSaveTask = Task {
            _ = await previous?.value
            do {
                try await captureStore.clearFormulas(); adoptFormulas([:])
                latex = ""; unicode = ""; unicodeMessage = ""
                status = "Formula history cleared. Capture images remain."
            } catch { problem = "Formula history could not be cleared: \(error.localizedDescription)" }
        }
    }
    func importFileIntoHistory(_ url: URL) async throws -> CaptureRecord {
        let stored = try await captureStore.add(file: url)
        try await accept(stored)
        return stored.record
    }
    func importImage(_ image: CGImage, notify: Bool = true) async throws {
        let stored = try await captureStore.add(image: image)
        try await accept(stored, notify: notify)
    }
    func pasteImage(recogniseText: Bool = false) {
        guard !busy, !shuttingDown else { return }
        formulaCapturePending = false
        guard let image = NSImage(pasteboard: .general),
              let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let cgImage = bitmap.cgImage else {
            problem = "No image was found on the clipboard."; return
        }
        busy = true; status = "Saving clipboard image…"
        importTask = Task {
            do {
                try await importImage(cgImage, notify: !recogniseText)
                busy = false; importTask = nil
                if recogniseText { recognise(formula: false) }
            } catch {
                busy = false; importTask = nil
                if error is CancellationError { status = "Capture processing cancelled." }
                else if !shuttingDown { problem = error.localizedDescription }
            }
        }
    }

    func warmCaptureSelection() {
        captureService.warmSelection()
        let languages = selectedOCRLanguages
        Task.detached(priority: .utility) { try? prepareTextRecognition(languages: languages) }
    }

    func capture(scrolling: Bool, action: CaptureAction = .image, fullScreen: Bool = false) {
        if (action == .formula || action == .unicode), !developerRuntimeOverrides, !formulaSetup.ready {
            if formulaSetup.working { status = "Preparing formula recognition. Try again in a moment."; return }
            status = "Prepare formula recognition in Settings → Formula."
            onFormulaSetupNeeded?(); return
        }
        guard !busy, !shuttingDown else { return }
        let displayRegion = fullScreen ? CaptureService.pointerDisplayRegion() : nil
        if fullScreen && displayRegion == nil { problem = "No display is available for capture."; return }
        formulaCapturePending = action == .formula || action == .unicode
        busy = true
        onCaptureVisibility?(false)
        status = fullScreen ? "Capturing the display…" : (scrolling ? "Select scrolling content only, excluding fixed headers and scrollbars." : "Drag to select a region. Press Esc to cancel.")
        let previousApp = NSWorkspace.shared.frontmostApplication
        let restore: () -> Void = { [weak self] in
            self?.busy = false; self?.scrollSession = nil
            self?.onCaptureVisibility?(true)
        }
        if !fullScreen { captureService.beginSelection(freeze: !scrolling, hideDesktopIcons: hideDesktopIcons) }
        captureTask = Task { [self] in
            defer { captureTask = nil; captureService.cancelSelection() }
            let selectedRegion: CaptureRegion?
            if fullScreen { selectedRegion = displayRegion }
            else { selectedRegion = await captureService.selectRegion() }
            guard let region = selectedRegion else {
                status = "Capture cancelled."; restore(); return
            }
            do {
                try Task.checkCancellation()
                if scrolling {
                    let capture = try await captureService.prepare(region, hideDesktopIcons: hideDesktopIcons)
                    try Task.checkCancellation()
                    let session = ScrollCaptureSession()
                    scrollSession = session
                    session.start(capture: capture, region: region, targetApplication: previousApp) { [weak self] result in
                        restore()
                        guard self?.shuttingDown != true else { return }
                        do {
                            if let image = try result.get(), let self {
                                self.busy = true; self.status = "Saving capture…"
                                self.importTask = Task {
                                    defer { self.importTask = nil }
                                    do { try await self.importImage(image, notify: action == .image); self.busy = false; await self.finishCapture(action: action) }
                                    catch { self.busy = false; if error is CancellationError { self.status = "Capture processing cancelled." } else if !self.shuttingDown { self.problem = error.localizedDescription } }
                                }
                            }
                            else { self?.status = "Scrolling capture cancelled." }
                        } catch { self?.problem = error.localizedDescription }
                    }
                } else {
                    let image = try await captureService.image(region, hideDesktopIcons: hideDesktopIcons)
                    restore()
                    busy = true; status = "Saving capture…"
                    try await importImage(image, notify: action == .image)
                    busy = false
                    await finishCapture(action: action)
                }
            } catch { if error is CancellationError { status = "Capture processing cancelled." } else if !shuttingDown { problem = error.localizedDescription }; restore() }
        }
    }

    func playCaptureFeedback(success: Bool) { if captureSounds { feedback.play(success: success) } }

    private func finishCapture(action: CaptureAction) async {
        defer { formulaCapturePending = false }
        switch action {
        case .image:
            playCaptureFeedback(success: true)
            if copyCapturedImages {
                busy = true
                await copyImage()
                busy = false
            }
        case .text: recognise(formula: false)
        case .formula: recognise(formula: true, outputFormat: preferredFormulaFormat)
        case .unicode: recognise(formula: true, outputFormat: .unicode)
        }
    }

    func recognise(formula: Bool, outputFormat: OutputFormat = .latex) {
        guard !busy, !shuttingDown, let url = imageURL else { return }
        if formula, !developerRuntimeOverrides, !formulaSetup.ready {
            status = "Prepare formula recognition with one download in Settings → Formula."
            onFormulaSetupNeeded?(); return
        }
        let selectedPython = developerRuntimeOverrides ? python : formulaSetup.python
        let selectedConfig = developerRuntimeOverrides ? config : formulaSetup.configuration
        let captureID = activeCaptureID, languages = selectedOCRLanguages, finnish = finnishTextMode, tesseractPath = textEngineExecutable
        busy = true
        if formula, let captureID {
            if formulaResults[captureID] == nil, formulaResults.count >= 8,
               let oldest = captures.reversed().first(where: { formulaResults[$0.id] != nil }) {
                formulaResults.removeValue(forKey: oldest.id)
            }
            formulaResults[captureID] = FormulaResult(format: outputFormat, style: preferredLatexStyle)
            onFormulaReady?(captureID)
        }
        status = formula ? "Recognising formula…" : "Recognising text…"
        recognitionJob = Task {
            defer { busy = false; recognitionJob = nil }
            do {
                try Task.checkCancellation()
                guard !shuttingDown else { throw CancellationError() }
                let task = Task.detached(priority: .userInitiated) {
                    let result = formula ? try recogniseFormulaResult(url, python: selectedPython, config: selectedConfig) : FormulaRecognition(latex: try recogniseText(url, languages: languages, finnish: finnish, tesseractPath: tesseractPath), confidence: nil)
                    try Task.checkCancellation()
                    return result
                }
                recognitionTask = task
                defer { recognitionTask = nil }
                let recognition = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
                let result = recognition.latex
                if task.isCancelled || shuttingDown { throw CancellationError() }
                if formula {
                    latex = result; format = outputFormat
                    let rendered = UnicodeMath.convert(result, italicVariables: true)
                    unicode = rendered.text
                    unicodeMessage = rendered.warnings.isEmpty
                        ? "Unicode approximates two-dimensional maths; LaTeX retains its structure."
                        : rendered.warnings.joined(separator: " ")
                    if let captureID {
                        let keynote = KeynoteLatex.convert(result)
                        formulaResults[captureID] = FormulaResult(phase: .ready, confidence: recognition.confidence, originalConfidence: recognition.confidence, originalLatex: result, model: recognition.model, confidenceMethod: recognition.confidenceMethod, diagnostics: recognition.diagnostics, latex: result, unicode: unicode,
                            keynote: LatexWhitespace.compact(keynote.text), keynoteWarning: keynote.warnings.joined(separator: " "), warning: unicodeMessage, format: outputFormat, style: preferredLatexStyle)
                        copyFormula(captureID)
                        let renderTask = Task { try await FormulaPreviewRenderer.shared.render(result) }
                        formulaRenderTask = renderTask
                        do {
                            let preview = try await renderTask.value
                            if task.isCancelled || shuttingDown { throw CancellationError() }
                            formulaResults[captureID]?.preview = preview
                        } catch is CancellationError { throw CancellationError() }
                        catch { formulaResults[captureID]?.previewError = error.localizedDescription }
                        formulaRenderTask = nil
                    } else { copyOutput() }
                } else {
                    // Invalidate any pending image copy before publishing the OCR result.
                    if copyRecognisedText {
                        clipboardRequest += 1
                        clipboard.clearContents()
                        guard clipboard.setString(result, forType: .string) else { throw BakerError(message: "The recognised text could not be copied. Try Copy again.") }
                    }
                    text = result; format = .text
                    status = copyRecognisedText ? "Text copied." : "Recognition complete."
                }
                playCaptureFeedback(success: true)
                onResultReady?()
            } catch is CancellationError {
                status = "Recognition cancelled."
                formulaRenderTask = nil
                if formula, let captureID {
                    if formulaResults[captureID]?.phase == .ready { formulaResults[captureID]?.previewError = "Preview cancelled. The recognised source remains available." }
                    else { formulaResults[captureID]?.phase = .failed; formulaResults[captureID]?.error = "Recognition cancelled. Try again when ready." }
                }
            } catch {
                status = "Recognition did not complete."
                if formula, let captureID {
                    formulaResults[captureID]?.phase = .failed
                    formulaResults[captureID]?.error = error.localizedDescription
                    if !shuttingDown { playCaptureFeedback(success: false) }
                } else if !shuttingDown { problem = error.localizedDescription }
            }
        }
    }

    private func persistFormula(_ id: UUID) {
        guard !switchingStorage, let result = formulaResults[id], result.phase == .ready else { return }
        let value = SavedFormula(id: id, originalLatex: result.originalLatex.isEmpty ? result.latex : result.originalLatex,
            latex: result.latex, unicodeOverride: result.unicodeOverride, model: result.model,
            confidenceMethod: result.confidenceMethod, confidence: result.confidence, diagnostics: result.diagnostics,
            format: result.format.rawValue, style: result.style.rawValue, unicodeText: result.unicode, originalConfidence: result.originalConfidence ?? result.confidence, savedAt: savedFormulas[id]?.savedAt ?? Date())
        guard savedFormulas[id] != value else { return }
        let previous = formulaSaveTask
        formulaSaveTask = Task {
            _ = await previous?.value
            do {
                try await captureStore.saveFormula(value)
                adoptFormulas(try await captureStore.maintainFormulas(limit: formulaHistoryLimit, days: formulaHistoryDays))
            } catch { problem = "Formula could not be saved: \(error.localizedDescription)" }
        }
    }
    func recogniseSavedFormula(_ record: CaptureRecord) {
        guard !busy, !shuttingDown else { return }
        imageURL = captureURL(record); activeCaptureID = record.id
        recognise(formula: true, outputFormat: preferredFormulaFormat)
    }
    func openSavedFormula(_ id: UUID) {
        guard !busy, !shuttingDown, let value = savedFormulas[id] else { return }
        if formulaResults[id]?.phase != .ready {
            if formulaResults.count >= 8, let oldest = captures.reversed().first(where: { formulaResults[$0.id] != nil }) { formulaResults.removeValue(forKey: oldest.id) }
            let converted = UnicodeMath.convert(value.latex, italicVariables: true), keynote = KeynoteLatex.convert(value.latex)
            formulaResults[id] = FormulaResult(phase: .ready, confidence: value.confidence, originalConfidence: value.originalConfidence, wasEdited: value.originalLatex != value.latex,
                originalLatex: value.originalLatex, model: value.model, confidenceMethod: value.confidenceMethod,
                diagnostics: value.diagnostics, unicodeOverride: value.unicodeOverride, latex: value.latex,
                unicode: value.unicodeOverride ?? converted.text, keynote: LatexWhitespace.compact(keynote.text),
                keynoteWarning: keynote.warnings.joined(separator: " "), warning: converted.warnings.joined(separator: " "),
                format: OutputFormat(rawValue: value.format) ?? .latex, style: LatexCopyStyle(rawValue: value.style) ?? .bare)
            busy = true
            formulaEditJob = Task {
                defer { busy = false; formulaEditJob = nil; formulaRenderTask = nil }
                guard !shuttingDown, !Task.isCancelled else { return }
                do {
                    let render = Task { try await FormulaPreviewRenderer.shared.render(value.latex) }
                    formulaRenderTask = render
                    let rendered = try await render.value
                    guard !shuttingDown, !Task.isCancelled, !render.isCancelled, formulaResults[id]?.latex == value.latex else { return }
                    formulaResults[id]?.preview = rendered
                } catch { formulaResults[id]?.previewError = error.localizedDescription }
            }
        }
        focusedFormulaID = id; onFormulaReady?(id)
    }
    func chooseFormulaFormat(_ id: UUID, _ selected: OutputFormat) {
        guard !switchingStorage, selected != .text, formulaResults[id]?.phase == .ready else { return }
        formulaResults[id]?.format = selected
        formulaPreferences.set(selected.rawValue, forKey: "formulaOutputFormat")
        if activeCaptureID == id { format = selected }
        copyFormula(id)
    }
    func chooseLatexStyle(_ id: UUID, _ style: LatexCopyStyle) {
        guard !switchingStorage, formulaResults[id]?.phase == .ready else { return }
        formulaResults[id]?.style = style
        formulaPreferences.set(style.rawValue, forKey: "formulaLatexStyle")
        copyFormula(id)
    }
    func editFormula(_ id: UUID) {
        guard !busy, !shuttingDown else { return }
        guard let result = formulaResults[id], result.phase == .ready else { return }
        activeCaptureID = id; latex = result.latex; unicode = result.unicode
        if let record = captures.first(where: { $0.id == id }) { imageURL = captureURL(record); image = NSImage(contentsOf: captureURL(record)) }
        format = result.format; unicodeMessage = result.warning
        onEditResult?()
    }
    func applyFormulaEdits() {
        guard !busy, let id = activeCaptureID, formulaResults[id]?.phase == .ready else { return }
        if format == .unicode {
            formulaResults[id]?.unicodeOverride = unicode
            formulaResults[id]?.unicode = unicode
            formulaResults[id]?.format = .unicode
            copyFormula(id)
            return
        }
        if formulaResults[id]?.latex != latex { formulaResults[id]?.confidence = nil; formulaResults[id]?.wasEdited = true }
        formulaResults[id]?.unicodeOverride = nil
        formulaResults[id]?.latex = latex
        let keynote = KeynoteLatex.convert(latex)
        formulaResults[id]?.keynote = LatexWhitespace.compact(keynote.text)
        formulaResults[id]?.keynoteWarning = keynote.warnings.joined(separator: " ")
        let converted = UnicodeMath.convert(latex, italicVariables: true)
        unicode = converted.text; unicodeMessage = converted.warnings.joined(separator: " ")
        formulaResults[id]?.unicode = unicode; formulaResults[id]?.warning = unicodeMessage
        formulaResults[id]?.format = format
        formulaResults[id]?.preview = nil; formulaResults[id]?.previewError = nil
        copyFormula(id)
        let source = latex
        busy = true
        formulaEditJob = Task {
            defer { busy = false; formulaRenderTask = nil; formulaEditJob = nil }
            guard !shuttingDown, !Task.isCancelled else { return }
            let task = Task { try await FormulaPreviewRenderer.shared.render(source) }
            formulaRenderTask = task
            do {
                let preview = try await task.value
                guard !task.isCancelled, !shuttingDown else { throw CancellationError() }
                formulaResults[id]?.preview = preview
            } catch { if !shuttingDown { formulaResults[id]?.previewError = error.localizedDescription } }
        }
    }
    func copyFormula(_ id: UUID) {
        persistFormula(id)
        guard let result = formulaResults[id], result.phase == .ready else { return }
        clipboardRequest += 1
        do {
            if result.format == .unicode {
                let item = try MathClipboard.item(text: result.unicode, font: selectedMathFont)
                clipboard.clearContents()
                guard clipboard.writeObjects([item]) else { throw BakerError(message: "Could not copy Unicode.") }
            } else {
                clipboard.clearContents()
                let text = result.format == .keynote ? result.keynote : result.format == .markdown ? LatexCopyStyle.displayDollar.format(result.latex) : result.style.format(result.latex)
                guard clipboard.setString(text, forType: .string) else { throw BakerError(message: "Could not copy the formula.") }
            }
            let message = "\(result.format.rawValue) copied"
            formulaResults[id]?.copyStatus = message
            status = message
        } catch {
            formulaResults[id]?.copyStatus = "Copy failed — try again"
            status = error.localizedDescription
        }
    }

    func copyOutput() {
        guard !output.isEmpty else { return }
        clipboardRequest += 1
        if format == .unicode {
            do {
                let item = try MathClipboard.item(text: unicode, font: selectedMathFont)
                clipboard.clearContents()
                guard clipboard.writeObjects([item]) else {
                    throw BakerError(message: "Could not copy the formula to the clipboard.")
                }
            } catch { problem = error.localizedDescription; return }
        } else {
            clipboard.clearContents()
            guard clipboard.setString(output, forType: .string) else { problem = "The result could not be copied."; return }
        }
        status = "\(format.rawValue) result copied."
    }
    func copyImage() async {
        guard let imageURL else { return }
        _ = await copyImageFile(imageURL)
    }
    func pinImage() {
        guard let image else { return }
        pinImage(image)
    }
    private func pinImage(_ image: NSImage) {
        pinWindows.removeAll { !$0.isVisible }
        let ratio = image.size.height / max(1, image.size.width)
        let size = CGSize(width: min(480, image.size.width), height: min(600, 480 * ratio))
        let window = NSPanel(contentRect: CGRect(origin: CGPoint(x: 100, y: 100), size: size),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Baker · Pinned image"
        window.isReleasedWhenClosed = false
        window.level = .floating; window.hidesOnDeactivate = false
        let view = NSImageView(frame: CGRect(origin: .zero, size: size))
        view.image = image; view.imageScaling = .scaleProportionallyUpOrDown
        window.contentView = view; window.orderFrontRegardless(); pinWindows.append(window)
    }
    func saveImage() {
        guard let imageURL else { return }
        saveImageFile(imageURL)
    }
    private func saveImageFile(_ imageURL: URL) {
        let panel = NSSavePanel(); panel.directoryURL = storageDirectory
        panel.nameFieldStringValue = imageURL.lastPathComponent
        if let type = UTType(filenameExtension: imageURL.pathExtension) { panel.allowedContentTypes = [type] }
        if panel.runModal() == .OK, let destination = panel.url {
            let staging = destination.deletingLastPathComponent().appendingPathComponent(".baker-save-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: staging) }
            do {
                guard destination.standardizedFileURL != imageURL.standardizedFileURL else { status = "Image already saved."; return }
                try FileManager.default.copyItem(at: imageURL, to: staging)
                if FileManager.default.fileExists(atPath: destination.path) {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
                } else { try FileManager.default.moveItem(at: staging, to: destination) }
                status = "Image saved."
            }
            catch { problem = error.localizedDescription }
        }
    }

    func record(format: RecordingFormat) {
        guard !busy, !shuttingDown else { return }
        busy = true
        onCaptureVisibility?(false)
        status = "Select a region to record. Press Esc to cancel."
        let restore = { [weak self] in
            guard self?.shuttingDown != true else { return }
            self?.onCaptureVisibility?(true)
        }
        captureService.beginSelection(freeze: false)
        captureTask = Task { [self] in
            defer { captureTask = nil; captureService.cancelSelection() }
            guard let region = await captureService.selectRegion() else {
                busy = false; status = "Recording cancelled."; restore(); return
            }
            do {
                try Task.checkCancellation()
                let capture = try await captureService.prepare(region, hideDesktopIcons: hideDesktopIcons)
                try Task.checkCancellation()
                guard !shuttingDown else { throw CancellationError() }
                let session = RecordingSession()
                recordingSession = session; isRecording = true
                session.start(capture: capture, region: region, format: format) { [weak self] result in
                    restore()
                    guard let self else { return }
                    self.busy = false; self.isRecording = false; self.recordingSession = nil
                    if self.shuttingDown {
                        if case .success(let url?) = result { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                        return
                    }
                    do {
                        if let url = try result.get() {
                            self.acceptExport(url, directory: url.deletingLastPathComponent(),
                                              summary: "\(format == .gif ? "GIF" : "Video") ready. Save the recording to keep it.")
                        } else { self.status = "Recording cancelled." }
                    } catch { self.problem = error.localizedDescription; self.status = "Recording did not complete." }
                }
                status = "Recording. Use the floating controls to stop or cancel."
            } catch {
                busy = false; isRecording = false; status = "Recording did not start."
                if error is CancellationError { status = "Recording cancelled." }
                else if !shuttingDown { problem = error.localizedDescription }
                restore()
            }
        }
    }

    func stopRecording() { recordingSession?.stop() }

    var preparedDocumentEngine: PDFDocumentEngine? {
        let resources = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
        if !developerRuntimeOverrides && pdfEngineSetup.working { return nil }
        if !developerRuntimeOverrides, let engine = pdfEngineSetup.engine { return engine }
        if !developerRuntimeOverrides, let root = resources.resourceURL?.appendingPathComponent("DocumentEngine"),
           FileManager.default.isExecutableFile(atPath: root.appendingPathComponent("python/bin/python3.12").path),
           FileManager.default.fileExists(atPath: root.appendingPathComponent("document-engine.json").path),
           let worker = resources.url(forResource: "document_worker", withExtension: "py") {
            return PDFDocumentEngine(python: root.appendingPathComponent("python/bin/python3.12"), worker: worker,
                                     configuration: root.appendingPathComponent("document-engine.json"))
        }
        guard developerRuntimeOverrides else { return nil }
        let selectedConfig = config, selectedPython = python
        let configuration = URL(fileURLWithPath: selectedConfig).deletingLastPathComponent().appendingPathComponent("document-engine.json")
        guard !selectedConfig.isEmpty, !selectedPython.isEmpty,
              FileManager.default.fileExists(atPath: configuration.path),
              let worker = resources.url(forResource: "document_worker", withExtension: "py") else { return nil }
        return PDFDocumentEngine(python: URL(fileURLWithPath: selectedPython), worker: worker, configuration: configuration)
    }

    func convertPDF(format: PDFExportFormat) {
        if let onOpenFiles { onOpenFiles(format); return }
        guard !busy, !shuttingDown else { return }
        guard preparedDocumentEngine != nil else { problem = "Prepare the optional PDF engine in Settings → PDF Conversion first."; return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("baker-document-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch { problem = error.localizedDescription; return }
        let destination = directory.appendingPathComponent(source.deletingPathExtension().lastPathComponent).appendingPathExtension(format.fileExtension)
        busy = true; isConvertingPDF = true; documentProgress = DocumentProgress()
        pendingDocumentDirectory = directory
        exportSummary = preparedDocumentEngine == nil ? "Extracting readable text. Structured document recognition is not prepared in this build." : "Reconstructing text, equations, tables and figures locally."
        status = "Preparing PDF…"; onExportReady?()
        var options = PDFConversionOptions(); options.recognitionLanguages = selectedOCRLanguages; options.finnishTextMode = finnishTextMode; options.tesseractExecutable = textEngineExecutable; options.documentEngine = preparedDocumentEngine
        let worker = Task.detached { [self] in
            try PDFConverter.convert(source: source, destination: destination, format: format, options: options,
                isCancelled: { Task.isCancelled }, progress: { [self] progress in
                    Task { @MainActor [self] in
                        guard self.isConvertingPDF else { return }
                        self.status = progress.message
                        self.documentProgress.update(progress)
                    }
                })
        }
        documentTask = worker
        Task {
            defer { busy = false; isConvertingPDF = false; documentTask = nil; pendingDocumentDirectory = nil }
            do {
                let report = try await worker.value
                if worker.isCancelled || shuttingDown { throw CancellationError() }
                let summary = "\(report.totalPages) pages · \(report.ocrPages) pages read with OCR. "
                    + (report.warnings.first ?? "")
                acceptExport(destination, directory: directory, summary: summary)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                if error is CancellationError || shuttingDown { status = "PDF conversion cancelled." }
                else { problem = error.localizedDescription; status = "PDF conversion did not complete." }
            }
        }
    }

    func cancelJob() {
        filesInbox.cancel()
        recognitionJob?.cancel(); formulaEditJob?.cancel(); recognitionTask?.cancel(); formulaRenderTask?.cancel(); documentTask?.cancel(); recordingSession?.cancel(); scrollSession?.cancel()
        importTask?.cancel(); captureTask?.cancel(); captureService.cancelSelection()
    }

    private func acceptExport(_ url: URL, directory: URL, summary: String) {
        if let previous = ownedExportDirectory { try? FileManager.default.removeItem(at: previous) }
        ownedExportDirectory = directory; exportURL = url; exportSummary = summary
        status = "\(url.pathExtension.uppercased()) ready. Save the file to keep it."
        onExportReady?()
    }

    func copyExport() {
        saveExport(copyToClipboard: true)
    }

    func saveExport() { saveExport(copyToClipboard: false) }

    private func saveExport(copyToClipboard: Bool) {
        guard let exportURL, !busy, !shuttingDown else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel(); panel.directoryURL = storageDirectory; panel.nameFieldStringValue = exportURL.lastPathComponent
        if let type = UTType(filenameExtension: exportURL.pathExtension) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        // Stage next to the destination for atomic replacement without loading a video into RAM.
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".baker-save-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            if ["md", "tex"].contains(exportURL.pathExtension.lowercased()) {
                try PDFExportBundle.save(source: exportURL, destination: destination)
            } else {
                try FileManager.default.copyItem(at: exportURL, to: staging)
                if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging) }
                else { try FileManager.default.moveItem(at: staging, to: destination) }
            }
            if copyToClipboard {
                clipboard.clearContents()
                guard clipboard.writeObjects(PDFExportBundle.filesForCopy(destination).map { $0 as NSURL }) else {
                    throw BakerError(message: "The file was saved, but could not be copied to the clipboard.")
                }
            }
            status = copyToClipboard ? "File saved and copied." : "File saved."
        } catch { problem = error.localizedDescription }
    }

    func shutdown() async {
        formulaSetup.cancel(); pdfEngineSetup.cancel()
        shuttingDown = true
        await filesInbox.close()
        await pdfEngineSetup.close()
        let recognition = recognitionTask, document = documentTask
        let recognitionOperation = recognitionJob, editOperation = formulaEditJob
        recognitionOperation?.cancel(); editOperation?.cancel()
        let rendering = formulaRenderTask
        rendering?.cancel()
        let capturing = captureTask
        capturing?.cancel()
        let importing = importTask
        importing?.cancel()
        let recording = recordingSession, scrolling = scrollSession
        captureService.cancelSelection()
        recognition?.cancel(); document?.cancel(); recording?.cancel()
        await scrolling?.cancelAndWait()
        _ = await capturing?.result
        _ = await importing?.result
        _ = await formulaSaveTask?.value
        _ = await recognition?.result
        _ = await recognitionOperation?.result
        _ = await editOperation?.result
        _ = await rendering?.result
        _ = await document?.result
        await recording?.cancelAndWait()
        cleanup()
    }

    func cleanup() {
        recognitionTask?.cancel()
        documentTask?.cancel()
        recordingSession?.cancel()
        scrollSession?.cancel()
        if let ownedImage { try? FileManager.default.removeItem(at: ownedImage) }
        if let ownedExportDirectory { try? FileManager.default.removeItem(at: ownedExportDirectory) }
        if let pendingDocumentDirectory { try? FileManager.default.removeItem(at: pendingDocumentDirectory) }
    }
}

extension Workbench {
    var presetsDirectory: URL { storageDirectory.appendingPathComponent("Presets", isDirectory: true) }

    func chooseStorageFolder() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Baker Save Folder"; panel.prompt = "Use Folder"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false; panel.directoryURL = storageDirectory
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { await self?.changeStorageDirectory(url) }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    func changeStorageDirectory(_ proposed: URL) async {
        guard !busy, !shuttingDown else { return }
        guard canChangeStorage?() != false else { problem = "Close the capture editor before changing the save folder."; return }
        let directory = proposed.standardizedFileURL.resolvingSymlinksInPath()
        guard directory != storageDirectory else { return }
        guard directory.isFileURL else { problem = "Choose a folder on this Mac or in Finder."; return }
        switchingStorage = true; busy = true
        defer { switchingStorage = false; busy = false }
        await flushFormulaHistory()
        do {
            let store = CaptureStore(directory: directory)
            try await store.prepareLocation()
            let records = try await store.records(), formulas = try await store.savedFormulas()
            guard !shuttingDown else { return }
            captureStore = store; storageDirectory = directory
            formulaPreferences.set(directory.path, forKey: "storageDirectory")
            clipboardRequest += 1
            thumbnailCache = [:]; formulaResults = [:]; savedFormulas = formulas; captures = records
            focusedFormulaID = nil; activeCaptureID = nil; imageURL = nil; image = nil
            text = ""; latex = ""; unicode = ""; unicodeMessage = ""
            onStorageChanged?()
            status = "Save folder changed. Existing files remain in their previous folder."
        } catch { problem = "The save folder was not changed: \(error.localizedDescription)" }
    }
    func settingsPreset() -> SettingsPreset {
        SettingsPreset(copyImages: copyCapturedImages, copyText: copyRecognisedText, openTextEditor: showResults,
            captureSounds: captureSounds, hideDesktopIcons: hideDesktopIcons, visibleCaptures: visibleCaptures,
            formulaHistoryLimit: formulaHistoryLimit, formulaHistoryDays: formulaHistoryDays, mathFont: mathFont,
            languages: selectedOCRLanguages, formulaFormat: preferredFormulaFormat.rawValue, latexStyle: preferredLatexStyle.rawValue)
    }
    func applySettingsPreset(_ preset: SettingsPreset) throws {
        try preset.validate()
        applyingPreset = true
        copyCapturedImages = preset.copyImages; copyRecognisedText = preset.copyText; showResults = preset.openTextEditor
        captureSounds = preset.captureSounds; hideDesktopIcons = preset.hideDesktopIcons; visibleCaptures = preset.visibleCaptures
        formulaHistoryLimit = preset.formulaHistoryLimit; formulaHistoryDays = preset.formulaHistoryDays; mathFont = preset.mathFont
        ocrLanguageSelection = preset.languages.joined(separator: ",")
        formulaPreferences.set(preset.formulaFormat, forKey: "formulaOutputFormat")
        formulaPreferences.set(preset.latexStyle, forKey: "formulaLatexStyle")
        applyingPreset = false
        applyFormulaRetention()
        status = "Preset loaded."
    }
    func saveSettingsPreset() {
        guard !busy else { return }
        let preset = settingsPreset(), directory = presetsDirectory
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        catch { problem = error.localizedDescription; return }
        let panel = NSSavePanel(); panel.title = "Save Baker Preset"; panel.directoryURL = directory
        panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Baker.json"
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(preset).write(to: url, options: .atomic); self?.status = "Preset saved."
            } catch { self?.problem = error.localizedDescription }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
    func loadSettingsPreset() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = "Load Baker Preset"; panel.directoryURL = presetsDirectory
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let self, !self.busy else { return }
            self.busy = true
            Task {
                defer { self.busy = false }
                do {
                    let preset = try await Task.detached { try SettingsPreset.read(url) }.value
                    try self.applySettingsPreset(preset)
                } catch { self.problem = "Preset not loaded: \(error.localizedDescription)" }
            }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
}
