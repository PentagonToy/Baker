import AppKit
import BakerCore
import SwiftUI
import UniformTypeIdentifiers

enum OCRPluginJob: String, CaseIterable {
    case formula, markdown, latex
    var title: String { switch self { case .formula: return "Formula OCR"; case .markdown: return "PDF → Markdown"; case .latex: return "PDF → LaTeX" } }
    var operation: String { self == .formula ? "formula" : "pdf" }
}

/// Only packages imported with native consent may run. Nothing is discovered or launched implicitly.
@MainActor final class OCRPlugins: ObservableObject {
    struct Entry: Codable, Identifiable, Sendable {
        let manifest: OCRPluginManifest
        let folder: URL
        let digest: String
        var id: String { manifest.id }
    }
    @Published private(set) var entries: [Entry]
    @Published private(set) var priorities: [String: String]
    var selection: String {
        let values = Set(OCRPluginJob.allCases.map { preferred(for: $0) })
        return values.count == 1 ? values.first ?? "" : "mixed"
    }
    struct Counts: Codable {
        var images = 0, documents = 0, pages = 0
        var since = Date()
    }
    @Published private(set) var counts: [String: Counts]
    @Published private(set) var running = false
    @Published var message = ""
    private let defaults: UserDefaults
    private var worker: Task<OCRPluginExecution, Error>?
    @Published private(set) var configuring = false
    private var configurationTask: Task<Void, Never>?
    private var setupWindow: PluginSetupWindow?
    private var probeTask: Task<Void, Never>?
    private let root: URL
    private let resourceDirectory: URL
    init(defaults: UserDefaults, resources: URL? = nil) {
        self.defaults = defaults
        resourceDirectory = resources ?? Bundle.main.resourceURL ?? Bundle.main.bundleURL
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Baker/Plugins")
        entries = defaults.data(forKey: PreferenceKeys.ocrPlugins.name).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        counts = defaults.data(forKey: PreferenceKeys.ocrPluginUsage.name).flatMap { try? JSONDecoder().decode([String: Counts].self, from: $0) } ?? [:]
        let legacy = defaults.string(forKey: PreferenceKeys.ocrPluginSelection.name) ?? ""
        priorities = defaults.data(forKey: PreferenceKeys.ocrPluginPriorities.name).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
            ?? Dictionary(uniqueKeysWithValues: OCRPluginJob.allCases.map { ($0.rawValue, legacy) })
        savePriorities()
    }
    func preferred(for job: OCRPluginJob) -> String {
        entries.first { $0.id == priorities[job.rawValue] && $0.manifest.operations.contains(job.operation) }?.id ?? ""
    }
    func selected(for operation: String, format: PDFExportFormat? = nil) -> Entry? {
        let job: OCRPluginJob
        if operation == "formula" { job = .formula }
        else if operation == "pdf", let format { job = format == .markdown ? .markdown : .latex }
        else { return nil }
        return entries.first { $0.id == preferred(for: job) }
    }
    private func savePriorities() {
        if let data = try? JSONEncoder().encode(priorities) {
            defaults.set(data, forKey: PreferenceKeys.ocrPluginPriorities.name)
            defaults.removeObject(forKey: PreferenceKeys.ocrPluginSelection.name)
        }
    }
    func select(_ id: String, job: OCRPluginJob? = nil) throws {
        guard !running, !configuring else { throw BakerError(message: "Wait for the plugin to finish or cancel it first.", code: .invalidState) }
        guard id == "local" || entries.contains(where: { $0.id == id }) else { throw BakerError(message: "Import and approve this plugin in Advanced first.", code: .configurationInvalid) }
        if let job, id != "local", !entries.contains(where: { $0.id == id && $0.manifest.operations.contains(job.operation) }) {
            throw BakerError(message: "This plugin does not support that job.", code: .configurationInvalid)
        }
        for choice in job.map({ [$0] }) ?? OCRPluginJob.allCases { priorities[choice.rawValue] = id == "local" ? "" : id }
        savePriorities()
    }
    func add() {
        guard !running, !configuring, entries.isEmpty else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false; panel.message = "Choose a plugin ZIP containing plugin.json."
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("baker-plugin-import-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 16 * 1024 * 1024 else { throw OCRPluginManifestError.archive }
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let resources = resourceDirectory
            let result = try runProcess(resources.appendingPathComponent("Runtime/python/bin/python3.12"),
                arguments: ["-I", "-B", resources.appendingPathComponent("plugin_unpack.py").path, source.path, staging.path], timeout: 10, maximumOutputBytes: 32_768)
            guard result.status == 0 else { throw OCRPluginManifestError.archive }
            let children = try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            let source = FileManager.default.fileExists(atPath: staging.appendingPathComponent("plugin.json").path) ? staging : (children.count == 1 ? children[0] : staging)
            let manifest = try OCRPluginManifest.read(source)
            let digest = try OCRPluginPackage.digest(source)
            guard !entries.contains(where: { $0.id == manifest.id }) else { throw OCRPluginManifestError.duplicate }
            guard Self.approve(manifest, python: resources.appendingPathComponent("Runtime/python/bin/python3.12")) else { return }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let folder = root.appendingPathComponent(manifest.id + "-" + UUID().uuidString)
            do {
                try FileManager.default.copyItem(at: source, to: folder)
                guard try OCRPluginPackage.digest(folder) == digest else { throw OCRPluginManifestError.changed }
                entries.append(Entry(manifest: manifest, folder: folder, digest: digest)); save()
                priorities = [:]; savePriorities()
                if counts[manifest.id] == nil { counts[manifest.id] = Counts(); saveUsage() }
                message = "Added. Choose it above when you want to use it."
            } catch { try? FileManager.default.removeItem(at: folder); throw error }
        } catch { message = error.localizedDescription }
    }
    private static func approve(_ manifest: OCRPluginManifest, python: URL) -> Bool {
        let alert = NSAlert(); alert.messageText = "Add \(manifest.name)?"
        let operations = manifest.operations.map { $0 == "pdf" ? "PDFs" : "formulas" }.joined(separator: " and ")
        alert.informativeText = "This plugin can read files and use the network with your user permissions. It handles selected \(operations) when enabled. Add only code you trust. Baker stays preferred until you choose Plugin first."
        let bundledPython = manifest.executable == "baker-python"
        let executable = bundledPython ? python.path : manifest.executable
        let arguments = (bundledPython ? ["-I", "-B"] : []) + manifest.arguments
        let program = String(URL(fileURLWithPath: executable).lastPathComponent.prefix(32))
        let summary = NSTextField(labelWithString: bundledPython ? "Runs with Baker Python." : "Runs " + String(reflecting: program) + ".")
        summary.font = .systemFont(ofSize: 12); summary.textColor = .secondaryLabelColor
        alert.accessoryView = summary
        alert.addButton(withTitle: "Add Plugin"); alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Execution Details…")
        while true {
            switch alert.runModal() {
            case .alertFirstButtonReturn: return true
            case .alertThirdButtonReturn:
                let info = NSAlert(); info.messageText = "Execution details"
                info.informativeText = "Arguments are passed directly without a shell. {plugin} identifies the installed package."
                let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 440, height: 160))
                text.string = "Executable\n" + String(reflecting: executable) + "\n\nArguments\n" + arguments.map { "• " + String(reflecting: $0) }.joined(separator: "\n")
                text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
                text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                text.isVerticallyResizable = true; text.autoresizingMask = [.width]; text.textContainer?.widthTracksTextView = true
                text.setAccessibilityLabel("Plugin executable and arguments")
                let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 440, height: 160))
                scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.documentView = text
                info.accessoryView = scroll; info.addButton(withTitle: "Back"); info.runModal()
            default: return false
            }
        }
    }
    func forget() {
        guard !running, !configuring, let entry = entries.first else { return }
        do { try PluginSecret.save("", id: entry.id) }
        catch { message = "Could not remove the saved key. The plugin remains registered; unlock Keychain and try again."; return }
        entries.removeAll(); priorities = [:]; savePriorities(); save()
        message = "Plugin and saved key removed. Plugin files and private settings remain on this Mac."
    }
    private func save() { if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: PreferenceKeys.ocrPlugins.name) } }
    func run(_ entry: Entry, operation: String, input: URL? = nil, destination: URL? = nil, format: PDFExportFormat? = nil, setupFile: URL? = nil) async throws -> OCRPluginExecution {
        guard worker == nil else { throw BakerError(message: "A plugin is already running.", code: .invalidState) }
        try Task.checkCancellation()
        guard !configuring || operation == "configure" else { throw BakerError(message: "Complete plugin setup first.", code: .invalidState) }
        let python = resourceDirectory.appendingPathComponent("Runtime/python/bin/python3.12")
        let apiKey = operation == "configure" ? nil : try PluginSecret.read(entry.id)
        let data = root.deletingLastPathComponent().appendingPathComponent("PluginData/" + entry.id)
        let task = Task.detached(priority: .userInitiated) {
            try OCRPluginRunner.run(folder: entry.folder, approvedDigest: entry.digest, python: python, dataDirectory: data,
                                    operation: operation, input: input, destination: destination, format: format, apiKey: apiKey, setupFile: setupFile)
        }
        worker = task; running = true
        defer { worker = nil; running = false }
        let result = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        try Task.checkCancellation()
        if operation == "formula" || operation == "pdf" {
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
        guard let entry = entries.first, !running, !configuring, probeTask == nil else { return }
        message = "Checking…"
        probeTask = Task { [weak self] in
            guard let self else { return }
            defer { probeTask = nil }
            do { _ = try await run(entry, operation: "probe"); message = "Plugin responded. No capture was sent." }
            catch { message = "The plugin could not connect. Check its settings or choose Local." }
        }
    }
    func configure() {
        guard let entry = entries.first, entry.manifest.configuration == true, !running, configurationTask == nil else { return }
        configuring = true; message = "Opening plugin setup…"
        configurationTask = Task { [weak self] in
            guard let self else { return }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("baker-setup-" + UUID().uuidString)
            do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
            catch { configuring = false; configurationTask = nil; message = "Could not open plugin setup."; return }
            let descriptor = directory.appendingPathComponent("window.json")
            let monitor = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    if let size = try? descriptor.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                       size.isRegularFile == true, (size.fileSize ?? Int.max) <= 4096,
                       let data = try? Data(contentsOf: descriptor), data.count <= 4096,
                       let object = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                       let raw = object["url"], let url = PluginSetupWindow.localURL(raw) {
                        guard let self, !Task.isCancelled else { return }
                        setupWindow = PluginSetupWindow(url: url, cancel: { [weak self] in self?.cancel() })
                        setupWindow?.show(); return
                    }
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
            }
            defer {
                monitor.cancel(); setupWindow?.dismiss(); setupWindow = nil
                try? FileManager.default.removeItem(at: directory)
                configurationTask = nil; configuring = false
            }
            do { _ = try await run(entry, operation: "configure", setupFile: descriptor); message = "Plugin setup completed. You can test the connection now." }
            catch {
                message = error is CancellationError ? "Plugin setup cancelled." : "Plugin setup did not complete. Try again when ready."
            }
        }
    }
    func cancel() { configurationTask?.cancel(); probeTask?.cancel(); worker?.cancel() }
    func close() async { let task = worker, probe = probeTask, configuration = configurationTask; cancel(); _ = await task?.result; _ = await probe?.result; _ = await configuration?.result }
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
            Group {
                Label("Plugin", systemImage: "puzzlepiece.extension").font(BakerTypography.section)
                if let entry = plugins.entries.first {
                    Text(entry.manifest.name).font(BakerTypography.section)
                    ForEach(OCRPluginJob.allCases, id: \.rawValue) { job in
                        HStack {
                            Text(job.title)
                            Spacer(minLength: 16)
                            BakerSegmentedPicker(title: job.title + " preferred provider", selection: Binding(get: { plugins.preferred(for: job) }, set: { value in
                                do { try plugins.select(value.isEmpty ? "local" : value, job: job) }
                                catch { plugins.message = "Wait for the current job before changing priority." }
                            }), choices: [("Baker", ""), ("Plugin first", entry.id)])
                                .frame(width: 240, height: 24)
                                .disabled(!entry.manifest.operations.contains(job.operation))
                        }
                    }
                    Text("Each job has its own priority. Baker handles unsupported jobs and failures.")
                        .font(BakerTypography.supporting).foregroundStyle(.secondary)
                    if entry.manifest.configuration != true {
                        HStack {
                            SecureField("API key (optional)", text: $state.apiKey).textFieldStyle(.roundedBorder)
                            Button("Save Key") {
                                do { try PluginSecret.save(state.apiKey, id: entry.id); state.apiKey = ""; state.keyMessage = "Key saved in Keychain." }
                                catch { state.keyMessage = "Could not save the key. Try again." }
                            }.disabled(state.apiKey.isEmpty)
                        }
                    }
                    HStack {
                        if entry.manifest.configuration == true { Button("Configure…", action: plugins.configure) }
                        Button("Test Connection", action: plugins.test)
                        Button(entry.manifest.configuration == true ? "Clear Credentials" : "Clear Key") {
                            do { try PluginSecret.save("", id: entry.id); state.keyMessage = "Saved credentials cleared." }
                            catch { state.keyMessage = "Could not remove the key." }
                        }
                        Spacer()
                        Button("Remove Plugin") { state.apiKey = ""; state.keyMessage = ""; plugins.forget() }
                            .help("Removes the plugin registration and Baker’s saved credentials. Files and usage remain on this Mac.")
                    }
                    let usage = plugins.counts[entry.id] ?? OCRPlugins.Counts()
                    Divider()
                    HStack {
                        Text("Usage").font(BakerTypography.section)
                        RecognitionProviderLabel(provider: entry.manifest.label)
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
            }.disabled(busy || plugins.running || plugins.configuring)
            if plugins.configuring {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Waiting for plugin setup…").font(BakerTypography.supporting).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel Setup", action: plugins.cancel)
                }
            }
        }.alert("Reset plugin usage?", isPresented: $state.confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Usage", role: .destructive) { if let entry = plugins.entries.first { plugins.resetUsage(entry.id) } }
        } message: { Text("Clear this plugin’s Baker counts and start again today. Provider billing and saved results remain.") }
        .onChange(of: plugins.entries.map(\.id)) { _, _ in state.apiKey = ""; state.keyMessage = "" }
    }
}
