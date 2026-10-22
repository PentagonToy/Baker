import AppKit
import BakerCore
import Darwin

/// Same-user, owner-only mailbox. A filesystem event wakes the app; no polling timer.
@MainActor final class BakerAutomationServer {
    private var watcher: DispatchSourceFileSystemObject?
    private var jobs: [UUID: Task<Void, Never>] = [:]
    private weak var model: Workbench?
    func start(_ model: Workbench) throws {
        self.model = model
        let folder = BakerAutomation.directory, files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try files.attributesOfItem(atPath: folder.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory, (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw FormulaAdapter.Failure(message: "Invalid automation directory.") }
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        // Recover abandoned client responses without touching capture/history files.
        for file in (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            guard file.lastPathComponent.hasSuffix(".response.json"), UUID(uuidString: String(file.lastPathComponent.dropLast(14))) != nil,
                  let values = try? files.attributesOfItem(atPath: file.path), values[.type] as? FileAttributeType == .typeRegular,
                  (values[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  let date = values[.modificationDate] as? Date, date.timeIntervalSinceNow < -86400 else { continue }
            try? files.removeItem(at: file)
        }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { throw FormulaAdapter.Failure(message: "Cannot watch automation directory.") }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in Task { @MainActor in self?.drain() } }
        source.setCancelHandler { close(fd) }
        watcher = source; source.resume(); drain()
    }
    func stop() { watcher?.cancel(); watcher = nil; jobs.values.forEach { $0.cancel() }; jobs.removeAll() }
    private func drain() {
        guard let model, !model.shuttingDown, jobs.count < 4 else { return }
        let folder = BakerAutomation.directory, files = FileManager.default
        for file in ((try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter({ $0.lastPathComponent.hasSuffix(".request.json") }).prefix(4 - jobs.count) {
            do {
                let attributes = try files.attributesOfItem(atPath: file.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular, (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(), (attributes[.size] as? Int ?? Int.max) <= 65536 else { throw FormulaAdapter.Failure(message: "Invalid request file.") }
                let request = try JSONDecoder().decode(BakerAutomation.Request.self, from: Data(contentsOf: file))
                guard file.lastPathComponent == request.id.uuidString + ".request.json", jobs[request.id] == nil else { throw FormulaAdapter.Failure(message: "Invalid request identity.") }
                try files.removeItem(at: file)
                jobs[request.id] = Task { [weak self] in
                    guard let self else { return }
                    let result: [String: Any]
                    do {
                        guard abs(request.issuedAt.timeIntervalSinceNow) < 300 else { throw FormulaAdapter.Failure(message: "Request expired. Submit a fresh command.") }
                        result = try await self.handle(request, model)
                    }
                    catch { result = ["ok": false, "error": error.localizedDescription] }
                    let output = folder.appendingPathComponent(request.id.uuidString + ".response.json")
                    if !files.fileExists(atPath: output.path), let data = try? JSONSerialization.data(withJSONObject: result.merging(["id": request.id.uuidString]) { old, _ in old }) {
                        try? data.write(to: output, options: [.atomic]); try? files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
                    }
                    self.jobs.removeValue(forKey: request.id); self.drain()
                }
            } catch { try? files.removeItem(at: file) }
        }
    }
    private func handle(_ r: BakerAutomation.Request, _ m: Workbench) async throws -> [String: Any] {
        func fail(_ message: String) throws -> Never { throw FormulaAdapter.Failure(message: message) }
        func input() throws -> URL {
            guard let path = r.path, path.hasPrefix("/"), !path.contains("\0") else { try fail("Provide an absolute local path.") }
            return URL(fileURLWithPath: path)
        }
        switch r.operation {
        case "status": return ["ok": true,"busy": m.busy,"recording": m.isRecording,"convertingPDF": m.isConvertingPDF,"status": m.status,"error": m.failure?.userDescription ?? "","captures": m.captures.count,"storage": m.storageDirectory.path]
        case "history":
            let entries = m.captures.dropFirst(max(0,r.offset ?? 0)).prefix(min(100,max(1,r.limit ?? 20)))
            return ["ok": true,"total": m.captures.count,"captures": entries.map { ["id": $0.id.uuidString,"path": m.captureURL($0).path,"width": $0.pixelWidth,"height": $0.pixelHeight,"formula": m.savedFormulas[$0.id]?.latex ?? ""] as [String: Any] }]
        case "result": return ["ok": true,"text": m.text,"latex": m.latex,"unicode": m.unicode,"status": m.status,"busy": m.busy,"export": m.exportURL?.path ?? ""]
        case "cancel": m.cancelJob(); return ["ok": true]
        case "stop": m.captureFlow.stopRecording(); return ["ok": true]
        default: break
        }
        guard !m.busy, !m.shuttingDown else { try fail("Baker is busy. Read status or cancel before retrying.") }
        switch r.operation {
        case "capture":
            let mode = r.format ?? "area"
            guard ["area","all","repeat","scroll","window","text","formula"].contains(mode) else { try fail("Unknown capture mode.") }
            m.capture(scrolling: mode == "scroll", action: mode == "text" ? .text : mode == "formula" ? .formula : .image, fullScreen: mode == "all", reuseArea: mode == "repeat", window: mode == "window")
        case "record":
            guard ["video","gif"].contains(r.format ?? "video") else { try fail("Choose video or gif.") }
            m.record(format: r.format == "gif" ? .gif : .video)
        case "import":
            m.busy = true; defer { m.busy = false }
            _ = try await m.importFileIntoHistory(try input())
        case "open-formula":
            guard let id = r.text.flatMap(UUID.init(uuidString:)), m.savedFormulas[id] != nil else { try fail("Provide a saved formula UUID using --text.") }; m.openSavedFormula(id)
        case "copy": m.copyOutput()
        case "clear-cache": m.clearPreviewCache()
        case "settings":
            guard let page = SettingsPage.allCases.first(where: { $0.rawValue.lowercased() == (r.text ?? "general").lowercased() }) else { try fail("Unknown settings page.") }; m.onSettingsNeeded?(page)
        case "pdf":
            let source = try input()
            guard let output = r.output, output.hasPrefix("/"), let format = PDFExportFormat(rawValue: r.format ?? "markdown"), !FileManager.default.fileExists(atPath: output), let engine = m.preparedDocumentEngine else { try fail("Prepare the PDF model and supply a new absolute --output path and markdown/latex format.") }
            m.busy = true; m.isConvertingPDF = true
            defer { m.busy = false; m.isConvertingPDF = false }
            var options = PDFConversionOptions(); options.documentEngine = engine; options.recognitionLanguages = m.selectedOCRLanguages
            let report = try await m.documentFlow.convert(source: source, destination: URL(fileURLWithPath: output), format: format, options: options) { m.documentProgress.update($0); m.status = $0.message }
            return ["ok": true,"output": report.destination.path,"pages": report.totalPages,"warnings": report.warnings]
        default: try fail("Unknown operation. Run baker help.")
        }
        return ["ok": true,"accepted": true,"status": m.status]
    }
}
