import AppKit
import BakerCore
import SwiftUI
import UniformTypeIdentifiers

struct InboxFile: Identifiable {
    enum Phase { case waiting, processing, ready, failed, cancelled }
    let id = UUID()
    let url: URL
    var phase: Phase = .waiting
    var message = "Waiting"
    var capture: CaptureRecord?
    var export: URL?
    var progress: DocumentProgress?
    var provider: String?
}

@MainActor
final class FilesWorkspaceWindow: NSWindow {
    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 740, height: 600), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        hidesOnDeactivate = false
        level = .normal
        collectionBehavior = [.fullScreenAuxiliary]
        isReleasedWhenClosed = false
        contentMinSize = NSSize(width: 680, height: 520)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class FilesInbox: ObservableObject {
    @Published var items: [InboxFile] = []
    @Published var pdfFormat: PDFExportFormat = .markdown
    @Published private(set) var running = false
    @Published var message = ""
    @Published var targeted = false
    private unowned let model: Workbench
    private var task: Task<Void, Never>?
    private var folders: [URL] = []
    weak var presentationWindow: NSWindow?
    private(set) var filePicker: NSOpenPanel?
    init(model: Workbench) { self.model = model }
    func add(_ urls: [URL]) {
        guard !running else { return }
        for url in urls {
            guard items.count < 50 else { message = "Add up to 50 files at a time."; break }
            guard url.isFileURL else { message = "Drop local image or PDF files."; continue }
            guard ["png", "jpg", "jpeg", "tif", "tiff", "heic", "heif", "bmp", "pdf"].contains(url.pathExtension.lowercased()) else {
                message = "Supported: PNG, JPEG, TIFF, HEIC, BMP and PDF."; continue
            }
            guard !items.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) else { continue }
            items.append(InboxFile(url: url))
        }
    }
    func browse() {
        guard !running, !model.busy else { return }
        if let filePicker { filePicker.makeKeyAndOrderFront(nil); return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]; panel.allowsMultipleSelection = true
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        filePicker = panel
        NSApp.activate(ignoringOtherApps: true)
        let completed: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel] response in
            guard let self else { return }
            if response == .OK, let panel { self.add(panel.urls) }
            self.filePicker = nil
        }
        if let window = presentationWindow {
            window.makeKeyAndOrderFront(nil)
            panel.beginSheetModal(for: window, completionHandler: completed)
        } else { panel.begin(completionHandler: completed) }
    }

    func clear() {
        guard !running else { return }
        folders.forEach { try? FileManager.default.removeItem(at: $0) }; folders = []; items = []; message = ""
    }
    func start() {
        guard !running, !model.busy, items.contains(where: { $0.phase == .waiting }) else { return }
        running = true
        let format = pdfFormat
        task = Task {
            var ownsBusy = false
            defer { running = false; if ownsBusy { model.busy = false }; task = nil }
            if items.contains(where: { $0.phase == .waiting && $0.url.pathExtension.lowercased() == "pdf" }), !model.canConvertDocument {
                do {
                    if !model.pdfEngineSetup.working {
                        guard model.pdfEngineSetup.available else { message = model.pdfEngineSetup.message; return }
                        let alert = NSAlert()
                        alert.messageText = "Download the PDF engine?"
                        alert.informativeText = "PDF conversion needs a one-time download of \(model.pdfEngineSetup.downloadSize) (\(model.pdfEngineSetup.installedSize) installed). Recognition then runs on this Mac. Your queued files will convert after installation."
                        alert.addButton(withTitle: "Download & Continue"); alert.addButton(withTitle: "Not Now")
                        guard alert.runModal() == .alertFirstButtonReturn else { message = "PDF files are waiting. Download the engine when you are ready."; return }
                    }
                    message = "Preparing PDF engine…"
                    try await model.pdfEngineSetup.waitUntilReady()
                    message = ""
                } catch { message = BakerError.wrapping(error).userDescription; return }
            }
            do {
                while model.busy {
                    message = "Waiting for the current capture…"
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                try Task.checkCancellation()
            } catch { message = "Processing cancelled. Your files remain in the list."; return }
            model.busy = true; ownsBusy = true
            for index in items.indices {
                if Task.isCancelled { break }
                guard items[index].phase == .waiting else { continue }
                items[index].phase = .processing; items[index].message = "Preparing…"
                items[index].progress = items[index].url.pathExtension.lowercased() == "pdf" ? DocumentProgress() : nil
                let source = items[index].url
                let access = source.startAccessingSecurityScopedResource()
                defer { if access { source.stopAccessingSecurityScopedResource() } }
                do {
                    if source.pathExtension.lowercased() == "pdf" {
                        guard model.canConvertDocument else { throw BakerError(message: "Install the PDF engine before converting PDFs.", code: .modelNotReady, recovery: .pdfSettings) }
                        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("baker-inbox-" + UUID().uuidString)
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                        folders.append(folder)
                        let destination = folder.appendingPathComponent(source.deletingPathExtension().lastPathComponent).appendingPathExtension(format.fileExtension)
                        var options = PDFConversionOptions(); options.recognitionLanguages = model.selectedOCRLanguages; options.finnishTextMode = model.finnishTextMode; options.tesseractExecutable = model.textEngineExecutable; options.documentEngine = model.preparedDocumentEngine
                        items[index].provider = "Baker · Local"
                        let report = try await model.convertDocument(source: source, destination: destination, format: format, options: options) { [weak self] progress in
                            guard let self, self.items.indices.contains(index), self.items[index].phase == .processing else { return }
                            self.items[index].progress?.update(progress); self.items[index].message = progress.message
                            if let provider = progress.provider { self.items[index].provider = provider }
                        }
                        try Task.checkCancellation()
                        items[index].provider = report.provider
                        items[index].export = report.destination
                        do {
                            let saved = try await model.fileExports.saveAutomatically(source: report.destination, directory: model.storageDirectory)
                            items[index].export = saved
                            let figureWarning = report.warnings.first { $0.contains("figures still use online links") }
                            items[index].message = "\(report.totalPages) pages · Saved to save folder" + (figureWarning.map { " · " + $0 } ?? "")
                            try? FileManager.default.removeItem(at: folder)
                            folders.removeAll { $0 == folder }
                        } catch {
                            items[index].message = "Converted, but automatic save failed. Use Save… to keep this result. " + BakerError.wrapping(error, fallback: .exportFailed).userDescription
                        }
                    } else {
                        items[index].capture = try await model.importFileIntoHistory(source)
                        items[index].message = "Saved to capture history"
                    }
                    items[index].phase = .ready
                } catch is CancellationError {
                    items[index].phase = .cancelled; items[index].message = "Cancelled"; break
                } catch {
                    items[index].phase = .failed; items[index].message = BakerError.wrapping(error).userDescription
                }
            }
            for index in items.indices where items[index].phase == .waiting {
                if Task.isCancelled { items[index].phase = .cancelled; items[index].message = "Cancelled" }
            }
            if !Task.isCancelled { model.playCaptureFeedback(success: !items.contains { $0.phase == .failed }) }
        }
    }
    func cancel() { task?.cancel() }
    func close() async {
        if let filePicker {
            if let parent = filePicker.sheetParent { parent.endSheet(filePicker, returnCode: .cancel) }
            else { filePicker.cancel(nil) }
            self.filePicker = nil
        }
        task?.cancel(); _ = await task?.value; clear() }
    func save(_ file: InboxFile) {
        guard !running, !model.busy, let source = file.export else { return }
        let panel = NSSavePanel(); panel.directoryURL = model.storageDirectory; panel.nameFieldStringValue = source.lastPathComponent
        if panel.runModal() == .OK, let destination = panel.url {
            guard source.standardizedFileURL != destination.standardizedFileURL else { message = "This result is already saved here."; return }
            running = true; model.busy = true; message = "Saving file…"
            task = Task {
                defer { running = false; model.busy = false; task = nil }
                do { try await model.fileExports.save(source: source, destination: destination); message = "Saved " + destination.lastPathComponent }
                catch is CancellationError { message = "Save cancelled." }
                catch { message = BakerError.wrapping(error, fallback: .exportFailed).userDescription }
            }
        }
    }
}

struct FilesWorkspace: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: Workbench
    @ObservedObject var inbox: FilesInbox
    @ObservedObject private var pdfSetup: PDFEngineSetup
    init(model: Workbench, inbox: FilesInbox) {
        self.model = model; self.inbox = inbox; self.pdfSetup = model.pdfEngineSetup
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Clipboard & Files").font(BakerTypography.title)
                    Text("Turn captures and documents into editable text.").font(BakerTypography.supporting).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clipboard Image") { model.pasteImage() }.disabled(model.busy)
                Button("Read Clipboard Text") { model.pasteImage(recogniseText: true) }.disabled(model.busy)
            }
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 30)).foregroundStyle(BakerTheme.accent)
                Text("Drop images and PDFs here").font(.headline)
                Text("Choose files, select an output, then convert. Originals stay in place.").font(BakerTypography.supporting).foregroundStyle(.secondary)
                Button("Choose Files…", action: inbox.browse).buttonStyle(BakerButtonStyle(prominent: inbox.items.isEmpty)).disabled(model.busy || inbox.running)
            }.frame(maxWidth: .infinity).padding(24)
                .background(inbox.targeted ? BakerTheme.accent.opacity(0.1) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(inbox.targeted ? BakerTheme.accent : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6])))
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $inbox.targeted) { providers in
                    guard !model.busy, !inbox.running else { return false }
                    for provider in providers.prefix(50) {
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, _ in
                            let url = (value as? URL) ?? (value as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                            if let url { Task { @MainActor in inbox.add([url]) } }
                        }
                    }
                    return true
                }
            HStack {
                Picker("PDF output", selection: $inbox.pdfFormat) {
                    Text("Markdown").tag(PDFExportFormat.markdown); Text("LaTeX").tag(PDFExportFormat.latex)
                }.frame(width: 220).disabled(model.busy || inbox.running)
                if !model.canConvertDocument {
                    Text("PDF model download required").font(BakerTypography.supporting).foregroundStyle(.secondary)
                } else if !inbox.items.contains(where: { $0.provider != nil }) {
                    RecognitionProviderLabel(provider: "Baker · Local")
                }
                Spacer()
                Button("Clear", action: inbox.clear).disabled(model.busy || inbox.running)
                if inbox.running { Button("Cancel", action: inbox.cancel) }
                else { Button("Convert Files", action: inbox.start).buttonStyle(BakerButtonStyle(prominent: true)).disabled(model.busy || !inbox.items.contains { $0.phase == .waiting }) }
            }
            if !model.canConvertDocument && inbox.items.contains(where: { $0.url.pathExtension.lowercased() == "pdf" }) {
                PDFEngineSetupView(setup: model.pdfEngineSetup, inUse: model.busy)
            }
            List(inbox.items) { file in
                HStack {
                    Image(systemName: file.url.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "photo")
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(file.url.lastPathComponent).lineLimit(1)
                            if let provider = file.provider { RecognitionProviderLabel(provider: provider) }
                        }
                        Text(file.message).font(BakerTypography.supporting).foregroundStyle(file.phase == .failed ? .red : .secondary).lineLimit(2).help(file.message)
                        if file.phase == .processing, let progress = file.progress { DocumentProgressView(progress: progress).frame(maxWidth: .infinity) }
                    }
                    Spacer()
                    if file.phase == .processing && file.progress == nil { ProgressView().controlSize(.small) }
                    if let export = file.export {
                        Button("Open") { NSWorkspace.shared.open(export) }
                        Button("Save As…") { inbox.save(file) }
                    }
                    if let capture = file.capture { Button("Formula") { model.selectCapture(capture, action: .formula) }.disabled(model.busy) }
                }.padding(.vertical, 4)
            }.scrollContentBackground(.hidden).background(BakerTheme.surface, in: RoundedRectangle(cornerRadius: 10))
            Text(inbox.message.isEmpty ? "Completed files save automatically. Use Save As… for another copy." : inbox.message).font(BakerTypography.supporting).foregroundStyle(.secondary)
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: inbox.targeted)
        .buttonStyle(BakerButtonStyle()).font(BakerTypography.body).tint(BakerTheme.accent).padding(20).foregroundStyle(BakerTheme.ink).background(BakerTheme.background).frame(minWidth: 680, minHeight: 520)
    }
}
