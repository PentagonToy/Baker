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
}

@MainActor
final class FilesWorkspaceWindow: NSWindow {
    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 740, height: 600), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        hidesOnDeactivate = false
        level = .floating
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
        running = true; model.busy = true
        let format = pdfFormat
        task = Task {
            defer { running = false; model.busy = false; task = nil }
            for index in items.indices {
                if Task.isCancelled { break }
                guard items[index].phase == .waiting else { continue }
                items[index].phase = .processing; items[index].message = "Processing…"
                let source = items[index].url
                let access = source.startAccessingSecurityScopedResource()
                defer { if access { source.stopAccessingSecurityScopedResource() } }
                do {
                    if source.pathExtension.lowercased() == "pdf" {
                        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("baker-inbox-" + UUID().uuidString)
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                        folders.append(folder)
                        let destination = folder.appendingPathComponent(source.deletingPathExtension().lastPathComponent).appendingPathExtension(format.fileExtension)
                        var options = PDFConversionOptions(); options.recognitionLanguages = model.selectedOCRLanguages; options.finnishTextMode = model.finnishTextMode; options.tesseractExecutable = model.textEngineExecutable
                        let worker = Task.detached {
                            try PDFConverter.convert(source: source, destination: destination, format: format, options: options, isCancelled: { Task.isCancelled })
                        }
                        let report = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                        try Task.checkCancellation()
                        items[index].export = report.destination
                        items[index].message = "\(report.totalPages) pages · \(format.rawValue.uppercased()) ready"
                    } else {
                        items[index].capture = try await model.importFileIntoHistory(source)
                        items[index].message = "Saved to capture history"
                    }
                    items[index].phase = .ready
                } catch is CancellationError {
                    items[index].phase = .cancelled; items[index].message = "Cancelled"; break
                } catch {
                    items[index].phase = .failed; items[index].message = error.localizedDescription
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
        guard let source = file.export else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = source.lastPathComponent
        if panel.runModal() == .OK, let destination = panel.url {
            do {
                let staging = destination.deletingLastPathComponent().appendingPathComponent(".baker-export-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: staging) }
                try FileManager.default.copyItem(at: source, to: staging)
                if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging) }
                else { try FileManager.default.moveItem(at: staging, to: destination) }
                message = "Saved " + destination.lastPathComponent
            } catch { message = error.localizedDescription }
        }
    }
}

struct FilesWorkspace: View {
    @ObservedObject var model: Workbench
    @ObservedObject var inbox: FilesInbox
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Clipboard & Files").font(.title2.weight(.semibold))
                Spacer()
                Button("Clipboard Image") { model.pasteImage() }.disabled(model.busy)
                Button("Read Clipboard Text") { model.pasteImage(recogniseText: true) }.disabled(model.busy)
            }
            VStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 30)).foregroundStyle(.secondary)
                Text("Drop images and PDFs here").font(.headline)
                Text("Select several files · originals stay in place").font(.caption).foregroundStyle(.secondary)
                Button("Choose Files…", action: inbox.browse).disabled(model.busy)
            }.frame(maxWidth: .infinity).padding(24)
                .background(inbox.targeted ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(inbox.targeted ? Color.accentColor : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6])))
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: $inbox.targeted) { providers in
                    guard !model.busy else { return false }
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
                }.frame(width: 220).disabled(model.busy)
                Text("PDF text extraction").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear", action: inbox.clear).disabled(model.busy)
                if inbox.running { Button("Cancel", action: inbox.cancel) }
                else { Button("Process Files", action: inbox.start).disabled(model.busy || !inbox.items.contains { $0.phase == .waiting }) }
            }
            List(inbox.items) { file in
                HStack {
                    Image(systemName: file.url.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "photo")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.url.lastPathComponent).lineLimit(1)
                        Text(file.message).font(.caption).foregroundStyle(file.phase == .failed ? .red : .secondary).lineLimit(2).help(file.message)
                    }
                    Spacer()
                    if file.phase == .processing { ProgressView().controlSize(.small) }
                    if file.export != nil { Button("Save…") { inbox.save(file) } }
                    if let capture = file.capture { Button("Formula") { model.selectCapture(capture, action: .formula) }.disabled(model.busy) }
                }.padding(.vertical, 4)
            }
            Text(inbox.message.isEmpty ? "Images are archived. Save PDF outputs before clearing this list or quitting." : inbox.message).font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(Color(nsColor: .windowBackgroundColor)).frame(minWidth: 680, minHeight: 520)
    }
}
