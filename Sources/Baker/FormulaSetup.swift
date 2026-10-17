import Foundation
import BakerCore
import SwiftUI

struct FormulaModelManifest: Decodable, Sendable {
    struct File: Decodable, Sendable { let bytes: Int; let sha256: String }
    let repository: String
    let revision: String
    let files: [String: File]
    var variant: String? = nil
    var bundledOnly: Bool? = nil
}

private final class ModelDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let update: @Sendable (Int64) -> Void
    init(update: @escaping @Sendable (Int64) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) { update(totalBytesWritten) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

@MainActor
final class FormulaSetup: ObservableObject {
    @Published private(set) var ready = false
    @Published private(set) var working = false
    @Published private(set) var progress = 0.0
    @Published private(set) var message = "Checking formula recognition…"
    private var job: Task<Void, Never>?
    let runtime: URL
    let directory: URL
    var python: String { runtime.appendingPathComponent("python/bin/python3.12").path }
    var configuration: String { directory.appendingPathComponent("baker-config.json").path }
    var usesBundledModel: Bool {
        (try? Self.manifest())?.bundledOnly == true || FileManager.default.fileExists(atPath: (Bundle.main.resourceURL?.appendingPathComponent("DocumentEngine/mfr/encoder_model.onnx").path ?? ""))
    }
    var runtimeAvailable: Bool { FileManager.default.isExecutableFile(atPath: python) }
    init(runtime: URL? = nil, root: URL? = nil) {
        self.runtime = runtime ?? Bundle.main.resourceURL!.appendingPathComponent("Runtime")
        let support = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Baker/Models")
        let variant = (try? Self.manifest())?.variant
        directory = support.appendingPathComponent(variant == "mlp-int8-v1" ? "mfr-1.5-mlp-int8-v1" : "mfr-1.5")
        refresh()
    }
    private static func manifest() throws -> FormulaModelManifest {
        let bundle = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
        guard let source = bundle.url(forResource: "formula-model", withExtension: "json") else { throw BakerError(message: "Baker's model download information is missing. Reinstall Baker.") }
        let value = try JSONDecoder().decode(FormulaModelManifest.self, from: Data(contentsOf: source))
        guard value.variant == nil || (value.variant == "mlp-int8-v1" && value.bundledOnly == true) else {
            throw BakerError(message: "The bundled formula variant is unsupported. Reinstall Baker.")
        }
        return value
    }
    nonisolated private static func verify(_ directory: URL, manifest: FormulaModelManifest) throws {
        for (name, file) in manifest.files {
            try ModelIntegrity.verify(directory.appendingPathComponent(name), bytes: file.bytes, sha256: file.sha256)
        }
    }
    nonisolated static func provisionBundledModel(_ source: URL, directory: URL, manifest: FormulaModelManifest) throws {
        try verify(source, manifest: manifest)
        let files = FileManager.default, parent = directory.deletingLastPathComponent()
        try files.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stage = parent.appendingPathComponent(".bundled-\(UUID().uuidString)")
        let backup = parent.appendingPathComponent(".previous-\(UUID().uuidString)")
        defer { try? files.removeItem(at: stage) }
        try files.copyItem(at: source, to: stage)
        let settings: [String: Any] = ["model_dir": directory.path, "threads": 2, "max_new_tokens": 256, "timeout_seconds": 45, "max_image_pixels": 12000000]
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]).write(to: stage.appendingPathComponent("baker-config.json"), options: .atomic)
        let existing = files.fileExists(atPath: directory.path)
        if existing { try files.moveItem(at: directory, to: backup) }
        do { try files.moveItem(at: stage, to: directory) }
        catch { if existing { try? files.moveItem(at: backup, to: directory) }; throw error }
        if existing { try? files.removeItem(at: backup) }
    }
    func refresh() {
        guard !working else { return }
        working = true
        job = Task { [self] in
            defer { working = false }
            guard runtimeAvailable else { message = "This build does not include the recognition engine. Install the complete Baker app."; return }
            do {
                let manifest = try Self.manifest(), directory = directory
                if !FileManager.default.fileExists(atPath: configuration) {
                    guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("DocumentEngine/mfr"),
                          FileManager.default.fileExists(atPath: bundled.appendingPathComponent("encoder_model.onnx").path) else {
                        message = manifest.bundledOnly == true ? "The included formula model is missing. Reinstall Baker." : "Download the formula model once. Recognition then runs offline."; return
                    }
                    message = "Preparing the included formula model…"
                    try await Task.detached { try Self.provisionBundledModel(bundled, directory: directory, manifest: manifest) }.value
                } else {
                    try await Task.detached { try Self.verify(directory, manifest: manifest) }.value
                }
                ready = true; message = "Ready · local formula recognition"
            } catch { ready = false; message = "The formula model needs repair. Use Repair Model below." }
        }
    }
    func prepare() {
        guard !working, runtimeAvailable else { return }
        working = true; progress = 0; message = "Preparing formula recognition…"
        job = Task { [self] in
            let files = FileManager.default
            let stage = directory.deletingLastPathComponent().appendingPathComponent(".download-\(UUID().uuidString)")
            defer { try? files.removeItem(at: stage); working = false }
            do {
                let manifest = try Self.manifest()
                if manifest.bundledOnly == true {
                    guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("DocumentEngine/mfr"),
                          files.fileExists(atPath: bundled.appendingPathComponent("encoder_model.onnx").path) else {
                        throw BakerError(message: "The included model is missing. Reinstall Baker.")
                    }
                    message = "Preparing the included formula model…"
                    try await Task.detached { try Self.provisionBundledModel(bundled, directory: self.directory, manifest: manifest) }.value
                    ready = true; progress = 1; message = "Ready · local formula recognition"
                    return
                }
                try files.createDirectory(at: stage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let options = URLSessionConfiguration.ephemeral
                options.timeoutIntervalForRequest = 60; options.timeoutIntervalForResource = 300
                let session = URLSession(configuration: options)
                defer { session.invalidateAndCancel() }
                let total = manifest.files.values.reduce(0) { $0 + $1.bytes }; var complete = 0
                for name in manifest.files.keys.sorted() {
                    try Task.checkCancellation()
                    let expected = manifest.files[name]!
                    message = "Downloading formula model… \(Int(progress * 100))%"
                    let url = URL(string: "https://huggingface.co/\(manifest.repository)/resolve/\(manifest.revision)/\(name)")!
                    let base = complete
                    let delegate = ModelDownloadProgress { [weak self] bytes in
                        Task { @MainActor in self?.progress = Double(base + min(expected.bytes, Int(bytes))) / Double(total) }
                    }
                    let (temporary, response) = try await session.download(from: url, delegate: delegate)
                    defer { try? files.removeItem(at: temporary) }
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.url?.scheme == "https" else { throw BakerError(message: "The model server could not complete the download. Try again later.") }
                    try await Task.detached { try ModelIntegrity.verify(temporary, bytes: expected.bytes, sha256: expected.sha256) }.value
                    try files.moveItem(at: temporary, to: stage.appendingPathComponent(name))
                    complete += expected.bytes; progress = Double(complete) / Double(total)
                }
                try Task.checkCancellation()
                let settings: [String: Any] = ["model_dir": directory.path, "threads": 2, "max_new_tokens": 256, "timeout_seconds": 45, "max_image_pixels": 12000000]
                try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]).write(to: stage.appendingPathComponent("baker-config.json"), options: .atomic)
                let backup = directory.deletingLastPathComponent().appendingPathComponent(".previous-\(UUID().uuidString)")
                let existing = files.fileExists(atPath: directory.path)
                if existing { try files.moveItem(at: directory, to: backup) }
                do { try files.moveItem(at: stage, to: directory) }
                catch { if existing { try? files.moveItem(at: backup, to: directory) }; throw error }
                if existing { try? files.removeItem(at: backup) }
                ready = true; message = "Ready · local formula recognition"
            } catch {
                message = Task.isCancelled ? "Download cancelled. You can try again at any time." : "Could not prepare recognition: \(error.localizedDescription)"
            }
        }
    }
    func cancel() { job?.cancel() }
    func remove() {
        guard !working else { return }
        do { if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }; ready = false; progress = 0; message = "Model removed. Your capture history remains." }
        catch { message = "Could not remove the formula model: \(error.localizedDescription)" }
    }
}

struct FormulaSetupView: View {
    @ObservedObject var setup: FormulaSetup
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(setup.ready ? "Formula recognition is ready" : "Prepare formula recognition", systemImage: setup.ready ? "checkmark.circle.fill" : "arrow.down.circle").font(.headline)
            Text(setup.message).font(.callout).fixedSize(horizontal: false, vertical: true)
            if setup.working {
                ProgressView(value: setup.progress)
                Button("Cancel", action: setup.cancel)
            } else {
                HStack {
                    Button(setup.ready ? "Repair Model" : (setup.usesBundledModel ? "Prepare Included Model" : "Download Model · 120 MB"), action: setup.prepare).disabled(!setup.runtimeAvailable)
                    if setup.ready { Button("Remove Model", action: setup.remove) }
                }
            }
            Text("Downloads from Hugging Face. Images stay on this Mac. The recognition engine is included; no Python installation is needed.").font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
    }
}
