import AppKit
import BakerCore
import SwiftUI
import UniformTypeIdentifiers

/// Only packages imported with native consent may run. Nothing is discovered or launched implicitly.
@MainActor final class OCRPlugins: ObservableObject {
    struct Entry: Codable, Identifiable, Sendable {
        let manifest: OCRPluginManifest
        let folder: URL
        let digest: String
        var id: String { manifest.id }
    }
    @Published private(set) var entries: [Entry]
    @Published var selection: String { didSet { defaults.set(selection, forKey: PreferenceKeys.ocrPluginSelection.name) } }
    struct Counts: Codable {
        var images = 0, documents = 0, pages = 0
        var since = Date()
    }
    @Published private(set) var counts: [String: Counts]
    @Published private(set) var running = false
    @Published var message = ""
    private let defaults: UserDefaults
    private var worker: Task<OCRPluginExecution, Error>?
    private var probeTask: Task<Void, Never>?
    private let root: URL
    init(defaults: UserDefaults) {
        self.defaults = defaults
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Baker/Plugins")
        entries = defaults.data(forKey: PreferenceKeys.ocrPlugins.name).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        counts = defaults.data(forKey: PreferenceKeys.ocrPluginUsage.name).flatMap { try? JSONDecoder().decode([String: Counts].self, from: $0) } ?? [:]
        selection = defaults.string(forKey: PreferenceKeys.ocrPluginSelection.name) ?? ""
    }
    func selected(for operation: String) -> Entry? { entries.first { $0.id == selection && $0.manifest.operations.contains(operation) } }
    func select(_ id: String) throws {
        guard !running else { throw BakerError(message: "Wait for the plugin to finish or cancel it first.", code: .invalidState) }
        guard id == "local" || entries.contains(where: { $0.id == id }) else { throw BakerError(message: "Import and approve this plugin in Advanced first.", code: .configurationInvalid) }
        selection = id == "local" ? "" : id
    }
    func add() {
        guard !running, entries.isEmpty else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false; panel.message = "Choose a plugin ZIP containing plugin.json."
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("baker-plugin-import-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 16 * 1024 * 1024 else { throw OCRPluginManifestError.archive }
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
            let result = try runProcess(resources.appendingPathComponent("Runtime/python/bin/python3.12"),
                arguments: ["-I", "-B", resources.appendingPathComponent("plugin_unpack.py").path, source.path, staging.path], timeout: 10, maximumOutputBytes: 32_768)
            guard result.status == 0 else { throw OCRPluginManifestError.archive }
            let children = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            let source = FileManager.default.fileExists(atPath: staging.appendingPathComponent("plugin.json").path) ? staging : (children.count == 1 ? children[0] : staging)
            let manifest = try OCRPluginManifest.read(source)
            let digest = try OCRPluginPackage.digest(source)
            guard !entries.contains(where: { $0.id == manifest.id }) else { throw OCRPluginManifestError.duplicate }
            let alert = NSAlert(); alert.messageText = "Add \(manifest.name)?"
            alert.informativeText = "This plugin runs code with your user permissions and can read files or use the network. When selected, it receives your \(manifest.operations.joined(separator: " and ")) inputs. Only add code you trust. Baker keeps Local selected until you choose a plugin."
            alert.addButton(withTitle: "Add Plugin"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let folder = root.appendingPathComponent(manifest.id + "-" + UUID().uuidString)
            do {
                try FileManager.default.copyItem(at: source, to: folder)
                guard try OCRPluginPackage.digest(folder) == digest else { throw OCRPluginManifestError.changed }
                entries.append(Entry(manifest: manifest, folder: folder, digest: digest)); save()
                if counts[manifest.id] == nil { counts[manifest.id] = Counts(); saveUsage() }
                message = "Added. Choose it above when you want to use it."
            } catch { try? FileManager.default.removeItem(at: folder); throw error }
        } catch { message = error.localizedDescription }
    }
    func forget() {
        guard !running else { return }
        entries.removeAll(); selection = ""; save()
        message = "Removed from Baker. Plugin files and private settings remain on this Mac."
    }
    private func save() { if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: PreferenceKeys.ocrPlugins.name) } }
    func run(_ entry: Entry, operation: String, input: URL? = nil, destination: URL? = nil, format: PDFExportFormat? = nil) async throws -> OCRPluginExecution {
        guard worker == nil else { throw BakerError(message: "A plugin is already running.", code: .invalidState) }
        try Task.checkCancellation()
        let python = (Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("Runtime/python/bin/python3.12")
        let apiKey = try PluginSecret.read(entry.id)
        let data = root.deletingLastPathComponent().appendingPathComponent("PluginData/" + entry.id)
        let task = Task.detached(priority: .userInitiated) {
            try OCRPluginRunner.run(folder: entry.folder, approvedDigest: entry.digest, python: python, dataDirectory: data,
                                    operation: operation, input: input, destination: destination, format: format, apiKey: apiKey)
        }
        worker = task; running = true
        defer { worker = nil; running = false }
        let result = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        try Task.checkCancellation()
        if operation != "probe" {
            var value = counts[entry.id] ?? Counts()
            if let report = result.report { value.documents += 1; value.pages += report.totalPages } else { value.images += 1 }
            counts[entry.id] = value
            saveUsage()
        }
        return result
    }
    private func saveUsage() {
        if let data = try? JSONEncoder().encode(counts) { defaults.set(data, forKey: PreferenceKeys.ocrPluginUsage.name) }
    }
    func resetUsage(_ id: String) {
        counts[id] = Counts()
        saveUsage()
    }
    func test() {
        guard let entry = entries.first(where: { $0.id == selection }), !running, probeTask == nil else { return }
        message = "Checking…"
        probeTask = Task { [weak self] in
            guard let self else { return }
            defer { probeTask = nil }
            do { _ = try await run(entry, operation: "probe"); message = "Plugin responded. No capture was sent." }
            catch { message = "The plugin could not connect. Check its settings or choose Local." }
        }
    }
    func cancel() { probeTask?.cancel(); worker?.cancel() }
    func close() async { let task = worker, probe = probeTask; cancel(); _ = await task?.result; _ = await probe?.result }
    private enum OCRPluginManifestError: LocalizedError {
        case duplicate, changed, archive
        var errorDescription: String? { self == .duplicate ? "Remove the existing plugin before importing a replacement." : self == .archive ? "Choose a valid plugin ZIP below 16 MB, without links or unsafe paths." : "The plugin changed while being imported. Try again." }
    }
}

@MainActor private final class PluginSettingsState: ObservableObject {
    @Published var confirmReset = false
    @Published var apiKey = ""
    @Published var keyMessage = ""
}
struct OCRPluginSettings: View {
    @ObservedObject var plugins: OCRPlugins
    let busy: Bool
    @StateObject private var state = PluginSettingsState()
    var body: some View {
        BakerSettingsSection {
            Label("Plugin", systemImage: "puzzlepiece.extension").font(BakerTypography.section)
            if let entry = plugins.entries.first {
                Toggle(entry.manifest.name, isOn: Binding(get: { plugins.selection == entry.id }, set: { plugins.selection = $0 ? entry.id : "" }))
                Text("Formula and PDF jobs use supported plugin operations. If a job fails, Baker tries its local model once. Cancelled jobs stay cancelled.")
                    .font(BakerTypography.supporting).foregroundStyle(.secondary)
                HStack {
                    SecureField("API key (optional)", text: $state.apiKey).textFieldStyle(.roundedBorder)
                    Button("Save Key") {
                        do { try PluginSecret.save(state.apiKey, id: entry.id); state.apiKey = ""; state.keyMessage = "Key saved in Keychain." }
                        catch { state.keyMessage = "Could not save the key. Try again." }
                    }.disabled(state.apiKey.isEmpty)
                }
                HStack {
                    Button("Test Connection", action: plugins.test)
                    Button("Clear Key") {
                        do { try PluginSecret.save("", id: entry.id); state.keyMessage = "Key removed." }
                        catch { state.keyMessage = "Could not remove the key." }
                    }
                    Spacer()
                    Button("Remove Plugin") { state.apiKey = ""; state.keyMessage = ""; plugins.forget() }
                }
                let usage = plugins.counts[entry.id] ?? OCRPlugins.Counts()
                Divider()
                HStack {
                    Text("Usage · " + entry.manifest.name).font(BakerTypography.section)
                    Spacer()
                    Text("Since " + usage.since.formatted(date: .abbreviated, time: .omitted)).font(BakerTypography.supporting).foregroundStyle(.secondary)
                    Button("Reset…") { state.confirmReset = true }
                }
                Text("\(usage.images) images · \(usage.documents) PDFs · \(usage.pages) pages")
                Text("Completed in Baker; not the provider’s billing balance.").font(BakerTypography.supporting).foregroundStyle(.secondary)
            } else {
                Text("Add one OCR plugin. It can use its own runtime or an online API.")
                    .font(BakerTypography.supporting).foregroundStyle(.secondary)
                Button(action: plugins.add) { Label("Add Plugin ZIP…", systemImage: "plus") }
            }
            Text("Third-party plugins follow their own terms and privacy policies. You are responsible for permissions, costs and use.")
                .font(BakerTypography.supporting).foregroundStyle(.secondary)
            if !plugins.message.isEmpty { Text(plugins.message).font(BakerTypography.supporting).foregroundStyle(.secondary) }
            if !state.keyMessage.isEmpty { Text(state.keyMessage).font(BakerTypography.supporting).foregroundStyle(.secondary) }
        }.alert("Reset plugin usage?", isPresented: $state.confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Usage", role: .destructive) { if let entry = plugins.entries.first { plugins.resetUsage(entry.id) } }
        } message: { Text("Clear this plugin’s Baker counts and start again today. Provider billing and saved results remain.") }
        .disabled(busy || plugins.running).onChange(of: plugins.selection) { _, _ in state.apiKey = ""; state.keyMessage = "" }
    }
}
