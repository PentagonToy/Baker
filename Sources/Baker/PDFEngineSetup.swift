import AppKit
import BakerCore
import Darwin
import SwiftUI

struct PDFEngineDescriptor: Codable, Sendable {
    let schema: Int
    let engine_id: String
    let architecture: String
    let minimum_macos: String
    let available: Bool
    let url: URL
    let archive_bytes: Int
    let archive_sha256: String
    let unpacked_bytes: Int
    let manifest_sha256: String
}

private final class PDFDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let limit: Int64
    let update: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var task: URLSessionTask?
    init(limit: Int64, update: @escaping @Sendable (Int64) -> Void) { self.limit = limit; self.update = update }
    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) { lock.lock(); self.task = task; lock.unlock() }
    func report() {
        lock.lock(); let current = task; lock.unlock()
        guard let current else { return }
        let bytes = current.countOfBytesReceived
        if bytes > limit || current.countOfBytesExpectedToReceive > limit { current.cancel() }
        else { update(bytes) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit { downloadTask.cancel() }
        else { update(totalBytesWritten) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

@MainActor
final class PDFEngineSetup: ObservableObject {
    @Published private(set) var ready = false
    @Published private(set) var failure: BakerError?
    @Published private(set) var working = false
    @Published private(set) var progress = 0.0
    @Published private(set) var message = "PDF conversion needs an optional download."
    @Published var confirmRemoval = false
    let descriptor: PDFEngineDescriptor?
    let directory: URL
    private var job: Task<Void, Never>?
    private let resources: URL
    var downloadSize: String { ByteCountFormatter.string(fromByteCount: Int64(descriptor?.archive_bytes ?? 0), countStyle: .file) }
    var installedSize: String { ByteCountFormatter.string(fromByteCount: Int64(descriptor?.unpacked_bytes ?? 0), countStyle: .file) }
    var available: Bool { descriptor?.available == true }

    init(resources: URL? = nil, support: URL? = nil) {
        let bundle = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
        self.resources = resources ?? bundle.resourceURL!
        descriptor = try? JSONDecoder().decode(PDFEngineDescriptor.self, from: Data(contentsOf: self.resources.appendingPathComponent("pdf-engine.json")))
        let base = support ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Baker/Engines")
        directory = base.appendingPathComponent(descriptor?.engine_id ?? "pdf-engine-v1.0.0")
        refresh()
    }
    func refresh() {
        guard !working else { return }
        let receipt = try? JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("installation.json"))) as? [String: String]
        ready = descriptor != nil && receipt?["archive_sha256"] == descriptor?.archive_sha256 && receipt?["engine_id"] == descriptor?.engine_id
            && FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent("python/bin/python3.12").path)
            && FileManager.default.fileExists(atPath: directory.appendingPathComponent("document-engine.json").path)
        message = ready ? "Installed · PDF recognition runs on this Mac." : (available ? "Download once to convert PDFs. Captures and formula recognition work without it." : "The separate PDF engine is being prepared and is not available to download yet.")
    }
    var engine: PDFDocumentEngine? {
        guard ready else { return nil }
        return PDFDocumentEngine(python: directory.appendingPathComponent("python/bin/python3.12"), worker: resources.appendingPathComponent("document_worker.py"), configuration: directory.appendingPathComponent("document-engine.json"))
    }
    func prepare() {
        guard !working, let descriptor, available else { return }
        failure = nil; working = true; progress = 0
        job = Task { [self] in
            let files = FileManager.default
            let stage = directory.deletingLastPathComponent().appendingPathComponent(".install-" + UUID().uuidString)
            let archive = files.temporaryDirectory.appendingPathComponent("baker-pdf-" + UUID().uuidString + ".tar.gz")
            defer { try? files.removeItem(at: archive); try? files.removeItem(at: stage); working = false }
            do {
                guard descriptor.schema == 1, descriptor.architecture == "arm64", descriptor.engine_id == directory.lastPathComponent,
                      descriptor.archive_bytes > 0, descriptor.unpacked_bytes > 0,
                      descriptor.url.scheme == "https", descriptor.url.host == "github.com",
                      descriptor.url.path.hasPrefix("/PentagonToy/Baker/releases/download/"),
                      descriptor.archive_sha256.count == 64, descriptor.manifest_sha256.count == 64 else { throw BakerError(message: "The PDF engine download information is invalid. Update Baker.", code: .configurationInvalid, recovery: .updateApp) }
                let minimum = descriptor.minimum_macos.split(separator: ".").compactMap { Int($0) }
                guard minimum.count >= 2, ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: minimum[0], minorVersion: minimum[1], patchVersion: minimum.count > 2 ? minimum[2] : 0)) else { throw BakerError(message: "This PDF engine needs macOS \(descriptor.minimum_macos) or later.", code: .unsupportedSystem) }
                try files.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let free = try directory.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
                guard free > Int64(descriptor.archive_bytes + descriptor.unpacked_bytes + 256 * 1_024 * 1_024) else { throw BakerError(message: "There is not enough free space to install the PDF engine.", code: .insufficientSpace) }
                message = "Downloading PDF engine…"
                let options = URLSessionConfiguration.ephemeral
                options.timeoutIntervalForRequest = 60; options.timeoutIntervalForResource = 7_200
                let session = URLSession(configuration: options)
                defer { session.invalidateAndCancel() }
                let delegate = PDFDownloadProgress(limit: Int64(descriptor.archive_bytes)) { [weak self] bytes in
                    Task { @MainActor in
                        guard let self, self.working else { return }
                        self.progress = min(1, Double(bytes) / Double(descriptor.archive_bytes))
                    }
                }
                // Async download tasks can omit didWriteData callbacks. Read the
                // task's received-byte counter as well so progress stays visible.
                let monitor = Task.detached {
                    while !Task.isCancelled {
                        delegate.report()
                        do { try await Task.sleep(nanoseconds: 250_000_000) } catch { break }
                    }
                }
                defer { monitor.cancel() }
                let (temporary, response) = try await session.download(from: descriptor.url, delegate: delegate)
                defer { try? files.removeItem(at: temporary) }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.url?.scheme == "https" else { throw BakerError(message: "The PDF engine server could not complete the download. Try again later.", code: .downloadFailed) }
                try files.moveItem(at: temporary, to: archive)
                try Task.checkCancellation()
                message = "Checking and installing PDF engine…"; progress = 1
                let python = resources.appendingPathComponent("Runtime/python/bin/python3.12")
                let installer = resources.appendingPathComponent("pdf_engine_install.py")
                let descriptorURL = resources.appendingPathComponent("pdf-engine.json")
                let worker = Task.detached { try Self.unpack(python: python, installer: installer, descriptor: descriptorURL, archive: archive, stage: stage) }
                try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                let extracted = stage.appendingPathComponent("PDFEngine")
                let backup = directory.deletingLastPathComponent().appendingPathComponent(".previous-" + UUID().uuidString)
                let existing = files.fileExists(atPath: directory.path)
                if existing { try files.moveItem(at: directory, to: backup) }
                do { try files.moveItem(at: extracted, to: directory) }
                catch { if existing { try? files.moveItem(at: backup, to: directory) }; throw error }
                if existing { try? files.removeItem(at: backup) }
                ready = true; message = "Installed · PDF recognition runs on this Mac."
            } catch {
                failure = Task.isCancelled ? nil : BakerError.wrapping(error, fallback: .downloadFailed)
                message = failure.map { "Could not install the PDF engine: " + $0.userDescription } ?? "Download cancelled."
            }
        }
    }
    nonisolated private static func unpack(python: URL, installer: URL, descriptor: URL, archive: URL, stage: URL) throws {
        let response = try runProcess(python, arguments: ["-I", "-B", installer.path, "--archive", archive.path, "--descriptor", descriptor.path, "--stage", stage.path], timeout: 600, maximumOutputBytes: 1_048_576)
        guard response.status == 0 else {
            throw BakerError(message: "The PDF engine could not be verified.", code: .integrityFailed,
                             diagnostic: response.diagnostic ?? String(data: response.output.suffix(1024), encoding: .utf8), recovery: .pdfSettings)
        }
    }

    func cancel() { job?.cancel() }
    func close() async { job?.cancel(); await job?.value }
    func waitUntilReady() async throws {
        if !working { prepare() }
        let pending = job
        await withTaskCancellationHandler(operation: { await pending?.value }, onCancel: { Task { @MainActor [weak self] in self?.cancel() } })
        try Task.checkCancellation()
        guard ready else { throw failure ?? BakerError(message: message, code: .modelNotReady, recovery: .pdfSettings) }
    }
    func remove() {
        guard !working else { return }
        do {
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            ready = false; progress = 0; failure = nil; refresh()
        } catch {
            failure = BakerError.wrapping(error, fallback: .storageFailed)
            message = "Could not remove the PDF engine: " + (failure?.userDescription ?? "Unknown error")
        }
    }
}

struct PDFEngineSetupView: View {
    @ObservedObject var setup: PDFEngineSetup
    var inUse = false
    var embedded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(setup.ready ? "PDF model installed" : "Download for PDF conversion", systemImage: setup.ready ? "checkmark.circle.fill" : "arrow.down.circle").font(BakerTypography.section).foregroundStyle(setup.ready ? BakerTheme.success : Color.primary)
            if !setup.ready || setup.working || setup.failure != nil { Text(setup.message).font(BakerTypography.supporting).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if setup.working {
                ProgressView(value: setup.progress)
                HStack { Text(setup.progress < 1 ? "\(Int(setup.progress * 100))% downloaded" : "Verifying files…").font(BakerTypography.supporting).foregroundStyle(.secondary); Spacer(); Button("Cancel", action: setup.cancel) }
            } else {
                HStack {
                    Button(setup.ready ? "Reinstall" : "Download · " + setup.downloadSize, action: setup.prepare).disabled(!setup.available || inUse)
                    if setup.ready {
                        Button("Remove…") { setup.confirmRemoval = true }.disabled(inUse)
                            .confirmationDialog("Remove the PDF engine?", isPresented: $setup.confirmRemoval) {
                                Button("Remove PDF Engine", role: .destructive, action: setup.remove)
                            } message: { Text("Your files and history remain. PDF conversion will need another download.") }
                    }
                }
                Text("Download: \(setup.downloadSize) · Installed: \(setup.installedSize)").font(BakerTypography.supporting).foregroundStyle(.secondary)
            }
            Text("Local PDF conversion only. Loads when needed.").font(BakerTypography.supporting).foregroundStyle(.secondary)
        }.padding(embedded ? 0 : 18).frame(maxWidth: .infinity, alignment: .leading).background(embedded ? Color.clear : BakerTheme.surface, in: RoundedRectangle(cornerRadius: 13))
    }
}
