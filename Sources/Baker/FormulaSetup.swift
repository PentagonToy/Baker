import Foundation
import BakerCore
import SwiftUI

struct FormulaModelManifest: Decodable, Sendable {
    struct File: Decodable, Sendable { let bytes: Int; let sha256: String; var remotePath: String? = nil }
    struct Archive: Decodable, Sendable { let url: URL; let bytes: Int; let sha256: String; let files: [String: File] }
    var archive: Archive? = nil
    let repository: String
    let revision: String
    let files: [String: File]
    var variant: String? = nil
    var bundledOnly: Bool? = nil
    var pathPrefix: String? = nil
}

private final class ModelDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let limit: Int64
    let update: @Sendable (Int64) -> Void
    init(limit: Int64, update: @escaping @Sendable (Int64) -> Void) { self.limit = limit; self.update = update }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) { if totalBytesWritten > limit || totalBytesExpectedToWrite > limit { downloadTask.cancel() } else { update(totalBytesWritten) } }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

@MainActor
final class FormulaSetup: ObservableObject {
    @Published private(set) var ready = false
    @Published private(set) var failure: BakerError?
    @Published private(set) var working = false
    @Published private(set) var progress = 0.0
    @Published private(set) var message = "Checking formula recognition…"
    private var job: Task<Void, Never>?
    let runtime: URL
    @Published private(set) var engine: FormulaEngine
    private let preferences: BakerPreferences
    private let root: URL
    private var mfrVariant: String?
    var directory: URL { root.appendingPathComponent(engine.directoryName(variant: mfrVariant)) }
    var downloadSize: String {
        let manifest = try? engine.manifest()
        let bytes = manifest?.archive?.bytes ?? manifest?.files.values.reduce(0) { $0 + $1.bytes } ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
    func select(_ value: FormulaEngine) {
        guard !working, engine != value else { return }
        engine = value; preferences[PreferenceKeys.formulaEngine] = value.rawValue
        ready = false; failure = nil; progress = 0; refresh()
    }
    var python: String { runtime.appendingPathComponent("python/bin/python3.12").path }
    var configuration: String { directory.appendingPathComponent("baker-config.json").path }
    var usesBundledModel: Bool {
        bundledModel != nil
    }
    private var bundledModel: URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        return engine.bundledPaths.map { resources.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("encoder_model.onnx").path) }
    }
    var runtimeAvailable: Bool { FileManager.default.isExecutableFile(atPath: python) }
    init(runtime: URL? = nil, root: URL? = nil, preferences: BakerPreferences = BakerPreferences()) {
        self.runtime = runtime ?? Bundle.main.resourceURL!.appendingPathComponent("Runtime")
        self.preferences = preferences
        engine = FormulaEngine(rawValue: preferences[PreferenceKeys.formulaEngine]) ?? .mfr
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("Baker/Models")
        mfrVariant = FormulaEngine.cachedMFRVariant(root: self.root)
        refresh()
    }
    nonisolated private static func verify(_ directory: URL, manifest: FormulaModelManifest) throws {
        for (name, file) in manifest.files {
            try ModelIntegrity.verify(directory.appendingPathComponent(name), bytes: file.bytes, sha256: file.sha256)
        }
    }
    nonisolated static func provisionBundledModel(_ source: URL, directory: URL, manifest: FormulaModelManifest, engine: FormulaEngine = .mfr) throws {
        try verify(source, manifest: manifest)
        let files = FileManager.default, parent = directory.deletingLastPathComponent()
        try files.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stage = parent.appendingPathComponent(".bundled-\(UUID().uuidString)")
        let backup = parent.appendingPathComponent(".previous-\(UUID().uuidString)")
        defer { try? files.removeItem(at: stage) }
        try files.copyItem(at: source, to: stage)
        let settings = engine.settings(directory: directory)
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
                let manifest = try engine.manifest(variant: mfrVariant), directory = directory, selectedEngine = engine
                if !FileManager.default.fileExists(atPath: configuration) {
                    guard let bundled = bundledModel,
                          FileManager.default.fileExists(atPath: bundled.appendingPathComponent("encoder_model.onnx").path) else {
                        message = manifest.bundledOnly == true ? "The included formula model is missing. Reinstall Baker." : "Download the formula model once. Recognition then runs offline."; return
                    }
                    message = "Preparing the included formula model…"
                    try await Task.detached { try Self.provisionBundledModel(bundled, directory: directory, manifest: manifest, engine: selectedEngine) }.value
                } else {
                    try await Task.detached { try Self.verify(directory, manifest: manifest) }.value
                }
                try Task.checkCancellation()
                ready = true; message = "Ready · local formula recognition"
            } catch { ready = false; failure = BakerError.wrapping(error, fallback: .integrityFailed); message = "The formula model needs repair. Use Repair Model below." }
        }
    }
    func prepare() {
        guard !working, runtimeAvailable else { return }
        failure = nil; working = true; progress = 0; message = "Preparing formula recognition…"
        job = Task { [self] in
            let files = FileManager.default
            let stage = root.appendingPathComponent(".download-\(UUID().uuidString)")
            defer { try? files.removeItem(at: stage); working = false }
            do {
                let manifest = try engine.manifest(), selectedEngine = engine
                let directory = root.appendingPathComponent(engine.directoryName(variant: manifest.variant))
                if manifest.bundledOnly == true {
                    guard let bundled = bundledModel,
                          files.fileExists(atPath: bundled.appendingPathComponent("encoder_model.onnx").path) else {
                        throw BakerError(message: "The included model is missing. Reinstall Baker.", code: .modelNotReady, recovery: .updateApp)
                    }
                    message = "Preparing the included formula model…"
                    try await Task.detached { try Self.provisionBundledModel(bundled, directory: directory, manifest: manifest, engine: selectedEngine) }.value
                    try Task.checkCancellation()
                    ready = true; progress = 1; message = "Ready · local formula recognition"
                    return
                }
                let options = URLSessionConfiguration.ephemeral
                options.timeoutIntervalForRequest = 60; options.timeoutIntervalForResource = 300
                let session = URLSession(configuration: options)
                defer { session.invalidateAndCancel() }
                if let archive = manifest.archive {
                    guard archive.url.scheme == "https", archive.url.host == "github.com",
                          archive.url.path.hasPrefix("/PentagonToy/Baker/releases/download/"),
                          archive.bytes > 0, archive.bytes <= 256_000_000 else {
                        throw BakerError(message: "The formula download information is invalid.", code: .configurationInvalid)
                    }
                    let delegate = ModelDownloadProgress(limit: Int64(archive.bytes)) { [weak self] bytes in
                        Task { @MainActor in
                            guard let self, self.working, self.engine == selectedEngine else { return }
                            self.progress = Double(bytes) / Double(archive.bytes)
                        }
                    }
                    let (temporary, response) = try await session.download(from: archive.url, delegate: delegate)
                    defer { try? files.removeItem(at: temporary) }
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.url?.scheme == "https" else {
                        throw BakerError(message: "The model server could not complete the download. Try again later.", code: .downloadFailed)
                    }
                    try Task.checkCancellation()
                    message = "Checking formula model…"
                    let pythonURL = URL(fileURLWithPath: python)
                    let bundle = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
                    guard let installer = bundle.url(forResource: "formula_model_install", withExtension: "py"),
                          let manifestURL = bundle.url(forResource: engine.resource, withExtension: "json") else {
                        throw BakerError(message: "The formula installer is missing. Reinstall Baker.", code: .configurationInvalid)
                    }
                    try files.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    let descriptor = stage.deletingLastPathComponent().appendingPathComponent(".manifest-\(UUID().uuidString).json")
                    defer { try? files.removeItem(at: descriptor) }
                    try files.copyItem(at: manifestURL, to: descriptor)
                    let worker = Task.detached {
                        let result = try runProcess(pythonURL, arguments: ["-I", "-B", installer.path, "--archive", temporary.path, "--manifest", descriptor.path, "--stage", stage.path], timeout: 120, maximumOutputBytes: 65536)
                        guard result.status == 0 else { throw BakerError(message: "The formula download could not be verified.", code: .integrityFailed) }
                    }
                    try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                } else {
                    try files.createDirectory(at: stage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    let total = manifest.files.values.reduce(0) { $0 + $1.bytes }; var complete = 0
                    for name in manifest.files.keys.sorted() {
                        try Task.checkCancellation()
                        let expected = manifest.files[name]!
                        message = "Downloading formula model… \(Int(progress * 100))%"
                        let remoteName = expected.remotePath ?? [manifest.pathPrefix, name].compactMap { $0 }.joined(separator: "/")
                        let url = URL(string: "https://huggingface.co/\(manifest.repository)/resolve/\(manifest.revision)/\(remoteName)")!
                        let base = complete
                        let delegate = ModelDownloadProgress(limit: Int64(expected.bytes)) { [weak self] bytes in
                            Task { @MainActor in
                                guard let self, self.working, self.engine == selectedEngine else { return }
                                self.progress = Double(base + min(expected.bytes, Int(bytes))) / Double(total)
                            }
                        }
                        let (temporary, response) = try await session.download(from: url, delegate: delegate)
                        defer { try? files.removeItem(at: temporary) }
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200, response.url?.scheme == "https" else { throw BakerError(message: "The model server could not complete the download. Try again later.", code: .downloadFailed) }
                        try await Task.detached { try ModelIntegrity.verify(temporary, bytes: expected.bytes, sha256: expected.sha256) }.value
                        try files.moveItem(at: temporary, to: stage.appendingPathComponent(name))
                        complete += expected.bytes; progress = Double(complete) / Double(total)
                    }
                }
                try Task.checkCancellation()
                let settings = engine.settings(directory: directory)
                try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]).write(to: stage.appendingPathComponent("baker-config.json"), options: .atomic)
                let backup = directory.deletingLastPathComponent().appendingPathComponent(".previous-\(UUID().uuidString)")
                let existing = files.fileExists(atPath: directory.path)
                if existing { try files.moveItem(at: directory, to: backup) }
                do { try files.moveItem(at: stage, to: directory) }
                catch { if existing { try? files.moveItem(at: backup, to: directory) }; throw error }
                if existing { try? files.removeItem(at: backup) }
                try Task.checkCancellation()
                if selectedEngine == .mfr { mfrVariant = manifest.variant }
                ready = true; message = "Ready · local formula recognition"
            } catch {
                failure = Task.isCancelled ? nil : BakerError.wrapping(error, fallback: .downloadFailed)
                message = failure.map { "Could not prepare recognition: " + $0.userDescription } ?? "Download cancelled."
            }
        }
    }
    func cancel() { job?.cancel() }
    func remove() {
        guard !working else { return }
        do { if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }; if engine == .mfr { mfrVariant = FormulaEngine.cachedMFRVariant(root: root) }; ready = false; progress = 0; message = "Model removed. Your capture history remains." }
        catch { message = "Could not remove the formula model: \(BakerError.wrapping(error, fallback: .storageFailed).userDescription)" }
    }
}

struct FormulaSetupView: View {
    @ObservedObject var setup: FormulaSetup
    var body: some View {
        BakerSettingsSection {
            HStack {
                Text("Local engine"); Spacer()
                Picker("Local engine", selection: Binding(get: { setup.engine }, set: setup.select)) {
                    ForEach(FormulaEngine.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 210, alignment: .trailing).disabled(setup.working)
            }.frame(minHeight: 30)
            HStack {
                Label(setup.ready ? "Ready on this Mac" : "Prepare formula recognition", systemImage: setup.ready ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(BakerTypography.section).foregroundStyle(setup.ready ? BakerTheme.success : Color.primary)
                Spacer()
                if setup.working { Button("Cancel", action: setup.cancel) }
                else if setup.ready {
                    Menu("Manage Model") {
                        Button("Repair Model", action: setup.prepare).disabled(!setup.runtimeAvailable)
                        Button("Remove Model", role: .destructive, action: setup.remove)
                    }.menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 12).frame(height: 32)
                        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(BakerTheme.border))
                } else {
                    Button(setup.usesBundledModel ? "Prepare Included Model" : "Download · " + setup.downloadSize, action: setup.prepare)
                        .buttonStyle(BakerButtonStyle(prominent: true)).disabled(!setup.runtimeAvailable)
                }
            }
            if setup.working { ProgressView(value: setup.progress) }
            if !setup.ready || setup.working || setup.failure != nil {
                Text(setup.message).font(BakerTypography.supporting).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(setup.engine.summary).font(BakerTypography.supporting).foregroundStyle(.secondary)
            Text("Downloaded separately. Used for local formula recognition.").font(BakerTypography.supporting).foregroundStyle(.secondary)
        }.buttonStyle(BakerButtonStyle())
    }
}
