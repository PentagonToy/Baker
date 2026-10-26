import AppKit
import BakerCore
import SwiftUI
import UniformTypeIdentifiers

extension Workbench {
    func copyImageFile(_ url: URL) async -> Bool {
        do {
            if url.pathExtension.lowercased() == "svg" {
                _ = try CaptureSVG(data: Data(contentsOf: url))
                try clipboardFlow.copyFiles([url]); status = "SVG copied."; return true
            }
            let copied = try await clipboardFlow.copyImage(url)
            if !shuttingDown { status = copied ? "Image copied." : "Clipboard changed. Copy again to replace it." }
            return copied
        } catch { report(error, fallback: .clipboardFailed); return false }
    }
    var output: String {
        switch format {
        case .text: return text
        case .latex: return (activeCaptureID.flatMap { formulaResults[$0]?.style } ?? preferredLatexStyle).format(latex)
        case .markdown: return LatexCopyStyle.displayDollar.format(latex)
        case .unicode: return unicode
        case .keynote: return LatexWhitespace.compact(KeynoteLatex.convert(latex).text)
        }
    }
    func copyOutput() {
        guard !output.isEmpty else { return }
        do {
            if format == .unicode { try clipboardFlow.copyMath(unicode, font: selectedMathFont) }
            else { try clipboardFlow.copyText(output) }
        } catch { report(error, fallback: .clipboardFailed); return }
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
    func pinImage(_ image: NSImage) {
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
    func saveImageFile(_ imageURL: URL) {
        guard !busy, !shuttingDown else { return }
        let panel = NSSavePanel(); panel.directoryURL = storageDirectory
        panel.nameFieldStringValue = imageURL.lastPathComponent
        if let type = UTType(filenameExtension: imageURL.pathExtension) { panel.allowedContentTypes = [type] }
        if panel.runModal() == .OK, let destination = panel.url {
            guard destination.standardizedFileURL != imageURL.standardizedFileURL else { status = "Image already saved."; return }
            busy = true; status = "Saving image…"
            Task {
                defer { busy = false }
                do { try await fileExports.save(source: imageURL, destination: destination); if !shuttingDown { status = "Image saved." } }
                catch is CancellationError { status = "Save cancelled." }
                catch { report(error, fallback: .exportFailed) }
            }
        }
    }
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
        guard canConvertDocument else { report(BakerError(message: "Prepare the optional PDF engine in Settings → Advanced → Offline Model first.", code: .modelNotReady, recovery: .pdfSettings)); return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("baker-document-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch { report(error, fallback: .recognitionFailed); return }
        let destination = directory.appendingPathComponent(source.deletingPathExtension().lastPathComponent).appendingPathExtension(format.fileExtension)
        busy = true; isConvertingPDF = true; documentProgress = DocumentProgress()
        documentProgress.provider = plugins.selected(for: "pdf")?.manifest.label ?? "Baker · Local"
        pendingDocumentDirectory = directory
        exportSummary = plugins.selected(for: "pdf") == nil ? "Reconstructing text, equations, tables and figures locally." : "Converting with the selected plugin."
        status = "Preparing PDF…"; onExportReady?()
        var options = PDFConversionOptions(); options.recognitionLanguages = selectedOCRLanguages; options.finnishTextMode = finnishTextMode; options.tesseractExecutable = textEngineExecutable; options.documentEngine = preparedDocumentEngine
        documentFlow.job = Task {
            defer { busy = false; isConvertingPDF = false; documentFlow.job = nil; pendingDocumentDirectory = nil }
            do {
                let report = try await convertDocument(source: source, destination: destination, format: format, options: options) { [weak self] progress in
                    guard let self, self.isConvertingPDF else { return }
                    self.status = progress.message; self.documentProgress.update(progress)
                }
                if Task.isCancelled || shuttingDown { throw CancellationError() }
                let summary = "\(report.totalPages) pages · \(report.ocrPages) pages read with OCR. "
                    + (report.warnings.first ?? "")
                do {
                    let saved = try await fileExports.saveAutomatically(source: report.destination, directory: storageDirectory)
                    try? FileManager.default.removeItem(at: directory)
                    acceptExport(saved, directory: nil, summary: "Saved to your save folder. " + summary, provider: report.provider)
                } catch {
                    acceptExport(report.destination, directory: directory, summary: "Automatic save failed. Save this result to keep it. " + summary, provider: report.provider)
                    self.report(error, fallback: .exportFailed)
                }
            } catch {
                try? FileManager.default.removeItem(at: directory)
                if error is CancellationError || shuttingDown { status = "PDF conversion cancelled." }
                else { report(error, fallback: .recognitionFailed); status = "PDF conversion did not complete." }
            }
        }
    }
    func cancelJob() {
        plugins.cancel(); filesInbox.cancel(); captureFlow.cancel(); recognitionFlow.cancel(); documentFlow.cancel(); fileExports.cancel(); importTask?.cancel()
    }
    func acceptExport(_ url: URL, directory: URL?, summary: String, provider: String? = nil) {
        if let previous = ownedExportDirectory { try? FileManager.default.removeItem(at: previous) }
        ownedExportDirectory = directory; exportURL = url; exportSummary = summary; exportProvider = provider
        status = directory == nil ? summary : "\(url.pathExtension.uppercased()) ready. Save the file to keep it."
        onExportReady?()
    }
    func copyExport() {
        saveExport(copyToClipboard: true)
    }
    func saveExport() { saveExport(copyToClipboard: false) }
    func saveExport(copyToClipboard: Bool) {
        guard let exportURL, !busy, !shuttingDown else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel(); panel.directoryURL = storageDirectory; panel.nameFieldStringValue = exportURL.lastPathComponent
        if let type = UTType(filenameExtension: exportURL.pathExtension) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        if exportURL.standardizedFileURL == destination.standardizedFileURL {
            do {
                if copyToClipboard { try clipboardFlow.copyFiles(PDFExportBundle.filesForCopy(exportURL)) }
                status = copyToClipboard ? "Saved file copied." : "This result is already saved here."
            } catch { report(error, fallback: .clipboardFailed) }
            return
        }
        busy = true; status = "Saving file…"
        Task {
            defer { busy = false }
            do {
                try await fileExports.save(source: exportURL, destination: destination)
                guard !shuttingDown else { return }
                if copyToClipboard { try clipboardFlow.copyFiles(PDFExportBundle.filesForCopy(destination)) }
                status = copyToClipboard ? "File saved and copied." : "File saved."
            } catch is CancellationError { status = "Save cancelled." }
            catch { report(error, fallback: .exportFailed) }
        }
    }
}
