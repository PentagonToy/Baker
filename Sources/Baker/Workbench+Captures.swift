import AppKit
import BakerCore
import SwiftUI
import UniformTypeIdentifiers

extension Workbench {
    func captureURL(_ record: CaptureRecord) -> URL { captureStore.directory.appendingPathComponent(record.fileName) }
    func originalPreview(_ record: CaptureRecord) async throws -> NSImage {
        let store = captureStore
        let raster = try await store.preview(record)
        guard captureStore === store, !Task.isCancelled else { throw CancellationError() }
        return NSImage(cgImage: raster, size: .zero)
    }
    func vectorImage(_ record: CaptureRecord) async throws -> NSImage {
        let store = captureStore, vector = try await store.vector(record)
        guard captureStore === store, !Task.isCancelled else { throw CancellationError() }
        guard let image = NSImage(data: vector.data) else { throw BakerError(message: "The saved vector could not be opened.", code: .previewFailed) }
        return image
    }
    func cachedThumbnail(_ id: UUID) -> NSImage? { library.cachedThumbnail(id) }
    func thumbnail(_ record: CaptureRecord) async throws -> NSImage {
        try await library.thumbnail(record, protecting: Set([activeCaptureID, focusedFormulaID].compactMap { $0 }))
    }
    func searchCaptures(_ query: String) async throws -> Set<UUID> { try await captureStore.search(query) }
    func revealCaptures() { NSWorkspace.shared.open(captureStore.directory) }
    func copyCapture(_ record: CaptureRecord) async -> Bool { await copyImageFile(captureURL(record)) }
    func confirmCaptureSaved(_ record: CaptureRecord) async -> Bool {
        do {
            _ = try await captureStore.thumbnail(record)
            status = "Saved to \(captureURL(record).deletingLastPathComponent().path)."
            return true
        } catch { report(error, fallback: .storageFailed); return false }
    }
    func saveCapture(_ record: CaptureRecord) { saveImageFile(captureURL(record)) }
    func selectCapture(_ record: CaptureRecord, action: CaptureAction) {
        guard !busy else { return }
        if (action == .formula || action == .unicode), savedFormulas[record.id] != nil {
            openSavedFormula(record.id); return
        }
        let url = captureURL(record)
        if record.isVector {
            guard action == .image else { status = "Edit this SVG as an image before recognising text or a formula."; return }
            do {
                let vector = try CaptureSVG(data: Data(contentsOf: url))
                let raster = try vector.raster(maximumPixelSize: max(vector.width, vector.height))
                pinImage(NSImage(cgImage: raster, size: .zero))
            } catch { report(error, fallback: .previewFailed) }
            return
        }
        guard let selected = NSImage(contentsOf: url) else { report(BakerError(message: "The saved image could not be opened.", code: .invalidInput)); return }
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
    func startImport(asFormula: Bool = false, _ operation: @escaping @MainActor () async throws -> Void) {
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
                else if !shuttingDown { report(error, fallback: .storageFailed) }
            }
        }
    }
    func accept(_ stored: StoredCapture, notify: Bool = true) async throws {
        try Task.checkCancellation()
        guard !shuttingDown else { throw CancellationError() }
        let url = captureURL(stored.record)
        guard let loaded = NSImage(contentsOf: url) else { throw BakerError(message: "The saved capture could not be opened.", code: .storageFailed) }
        let records = try await captureStore.records()
        try Task.checkCancellation()
        guard !shuttingDown else { throw CancellationError() }
        captures = records; historyRevision &+= 1
        library.remember(stored, records: captures)
        imageURL = url; image = loaded; activeCaptureID = stored.record.id
        text = ""; latex = ""; unicode = ""; unicodeMessage = ""; format = .text
        status = "Capture saved."
        if notify { onImageReady?() }
        historyNeedsMaintenance = true
    }
    func saveEditedCapture(_ image: CGImage, vector: CaptureSVG? = nil, replacing record: CaptureRecord) async throws -> CaptureRecord {
        guard !busy, !shuttingDown else { throw BakerError(message: "Wait for the current operation before saving edits.", code: .invalidState) }
        busy = true; defer { busy = false }
        await flushFormulaHistory()
        let stored: StoredCapture
        if let vector { stored = try await captureStore.replace(vector: vector, record: record) }
        else { stored = try await captureStore.replace(image: image, record: record) }
        savedFormulas.removeValue(forKey: record.id); formulaResults.removeValue(forKey: record.id)
        if focusedFormulaID == record.id { focusedFormulaID = nil }
        try await accept(stored, notify: false)
        if copyCapturedImages { _ = await copyCapture(stored.record) }
        status = "Capture overwritten. Previous OCR result removed."
        return stored.record
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
        guard let image = NSImage(pasteboard: clipboardFlow.pasteboard),
              let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let cgImage = bitmap.cgImage else {
            report(BakerError(message: "No image was found on the clipboard.", code: .clipboardFailed)); return
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
                else if !shuttingDown { report(error, fallback: .storageFailed) }
            }
        }
    }
    func warmCaptureSelection() {
        captureFlow.warmSelection()
        recognitionFlow.warmText(languages: selectedOCRLanguages)
    }
    func capture(scrolling: Bool, action: CaptureAction = .image, fullScreen: Bool = false, reuseArea: Bool = false, window: Bool = false) {
        if (action == .formula || action == .unicode), !developerRuntimeOverrides, !formulaSetup.ready {
            if formulaSetup.working { status = "Preparing formula recognition. Try again in a moment."; return }
            status = "Prepare formula recognition in Settings → Formula."
            onFormulaSetupNeeded?(); return
        }
        guard !busy, !shuttingDown else { return }
        let displayRegion = fullScreen ? CaptureService.pointerDisplayRegion() : (reuseArea ? previousArea?.resolve() : nil)
        if reuseArea && displayRegion == nil { status = "Select an area again: the saved display or its size has changed."; return }
        if fullScreen && displayRegion == nil { report(BakerError(message: "No display is available for capture.", code: .captureFailed)); return }
        formulaCapturePending = action == .formula || action == .unicode
        busy = true
        onCaptureVisibility?(false)
        status = window ? "Choose a window to capture." : reuseArea ? "Capturing the saved area…" : fullScreen ? "Capturing the display…" : (scrolling ? "Select scrolling content only, excluding fixed headers and scrollbars." : "Drag to select a region. Press Esc to cancel.")
        captureFlow.capture(region: displayRegion, scrolling: scrolling, hideDesktopIcons: hideDesktopIcons, window: window) { [weak self] result in
            guard let self else { return }
            self.onCaptureVisibility?(true)
            guard !self.shuttingDown else { return }
            do {
                guard let frame = try result.get() else { self.busy = false; self.status = "Capture cancelled."; return }
                self.status = "Saving capture…"
                self.importTask = Task {
                    defer { self.importTask = nil }
                    do {
                        try await self.importImage(frame.image, notify: action == .image)
                        if !window && !scrolling && !fullScreen && !reuseArea, let area = RepeatCaptureArea(region: frame.region) {
                            area.save(defaults: self.preferences.defaults); self.previousArea = area
                        }
                        self.busy = false; await self.finishCapture(action: action)
                    } catch {
                        self.busy = false
                        if error is CancellationError { self.status = "Capture processing cancelled." }
                        else if !self.shuttingDown { self.report(error, fallback: .captureFailed) }
                    }
                }
            } catch {
                self.busy = false
                if error is CancellationError { self.status = "Capture cancelled." }
                else { self.report(error, fallback: .captureFailed) }
            }
        }
    }
    func playCaptureFeedback(success: Bool) { if captureSounds { feedback.play(success: success) } }
    func finishCapture(action: CaptureAction) async {
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
    func record(format: RecordingFormat? = nil) {
        guard !busy, !shuttingDown else { return }
        busy = true; onCaptureVisibility?(false)
        status = "Select a region to record. Press Esc to cancel."
        captureFlow.record(format: format, hideDesktopIcons: hideDesktopIcons, started: { [weak self] in
            self?.isRecording = true; self?.status = "Recording. Use the floating controls to stop or cancel."
        }) { [weak self] result in
            guard let self else { return }
            self.busy = false; self.isRecording = false; self.onCaptureVisibility?(true)
            if self.shuttingDown {
                if case .success(let clip?) = result { try? FileManager.default.removeItem(at: clip.url.deletingLastPathComponent()) }
                return
            }
            do {
                if let clip = try result.get() {
                    self.saveRecording(clip.url)
                } else { self.status = "Recording cancelled." }
            } catch {
                if error is CancellationError { self.status = "Recording cancelled." }
                else { self.report(error, fallback: .recordingFailed); self.status = "Recording did not complete." }
            }
        }
    }
    func stopRecording() { captureFlow.stopRecording() }
}


extension Workbench {
    func recordingURL(_ record: RecordingRecord) -> URL { storageDirectory.appendingPathComponent(record.fileName) }
    func recordingThumbnail(_ record: RecordingRecord) async throws -> NSImage {
        let source = captureStore
        let raster = try await source.recordingThumbnail(record)
        guard source === captureStore, !Task.isCancelled else { throw CancellationError() }
        return NSImage(cgImage: raster, size: .zero)
    }
    func copyRecording(_ record: RecordingRecord) -> Bool {
        do { try clipboardFlow.copyFiles([recordingURL(record)]); return true }
        catch { report(error, fallback: .clipboardFailed); return false }
    }
    func saveRecording(_ source: URL) {
        busy = true; status = "Saving recording…"
        let store = captureStore
        importTask = Task {
            defer { busy = false; importTask = nil }
            do {
                let record = try await store.addRecording(source)
                let values = try await store.recordings()
                try? FileManager.default.removeItem(at: source.deletingLastPathComponent())
                guard !shuttingDown else { return }
                recordings = values; historyRevision &+= 1
                acceptExport(recordingURL(record), directory: nil, summary: "Recording saved in your capture folder.")
            } catch {
                // Keep the temporary recording available for manual recovery.
                if !shuttingDown { acceptExport(source, directory: nil, summary: "Automatic save failed. Save this recording to keep it."); report(error, fallback: .storageFailed) }
            }
        }
    }
}
