struct PreferenceKey { let name: String }
enum PreferenceKeys {
    static let ocrPlugins = PreferenceKey(name: "ocrPlugins")
    static let ocrPluginUsage = PreferenceKey(name: "ocrPluginUsage")
    static let ocrPluginSelection = PreferenceKey(name: "ocrPluginSelection")
    static let ocrPluginPriorities = PreferenceKey(name: "ocrPluginPriorities")
}
enum PluginSecret {
    static var fail = false
    static var reads = 0
    static var deleted: [String] = []
    static func read(_ id: String) throws -> String? { reads += 1; return nil }
    static func save(_ value: String, id: String) throws {
        if fail { throw BakerError(message: "Synthetic key failure", code: .storageFailed) }
        precondition(value.isEmpty); deleted.append(id)
    }
}
@MainActor func registryChecks() async throws {
    var checks = 0
    func check(_ value: Bool) { precondition(value); checks += 1 }
    check(PluginSetupWindow.localURL("http://127.0.0.1:52300/token") != nil)
    for raw in ["https://example.com/login", "http://localhost:52300/token", "file:///tmp/page", "http://127.0.0.1:80/token", "http://user:pass@127.0.0.1:52300/token", "http://127.0.0.1:52300/token#x"] {
        check(PluginSetupWindow.localURL(raw) == nil)
    }
    let name = "BakerPluginRegression." + UUID().uuidString
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let manifest = OCRPluginManifest(schema: 1, id: "example.remove", name: "Example", version: "1", executable: "baker-python", arguments: [], operations: ["formula", "pdf"], timeoutSeconds: 1)
    let entry = OCRPlugins.Entry(manifest: manifest, folder: URL(fileURLWithPath: "/unused"), digest: "unused")
    defaults.set(try JSONEncoder().encode([entry]), forKey: PreferenceKeys.ocrPlugins.name)
    defaults.set(entry.id, forKey: PreferenceKeys.ocrPluginSelection.name)
    let plugins = OCRPlugins(defaults: defaults)
    check(OCRPluginJob.allCases.allSatisfy { plugins.preferred(for: $0) == entry.id })
    check(defaults.object(forKey: PreferenceKeys.ocrPluginSelection.name) == nil)
    try plugins.select("local", job: .markdown)
    check(plugins.selected(for: "formula")?.id == entry.id)
    check(plugins.selected(for: "pdf", format: .markdown) == nil)
    check(plugins.selected(for: "pdf", format: .latex)?.id == entry.id)
    check(plugins.selection == "mixed")
    let restored = OCRPlugins(defaults: defaults)
    check(restored.preferred(for: .markdown).isEmpty && restored.preferred(for: .latex) == entry.id)
    try plugins.select("local")
    check(OCRPluginJob.allCases.allSatisfy { plugins.preferred(for: $0).isEmpty })
    try plugins.select(entry.id, job: .formula)
    check(plugins.preferred(for: .formula) == entry.id && plugins.preferred(for: .latex).isEmpty)
    PluginSecret.fail = true; plugins.forget()
    check(plugins.entries.count == 1 && plugins.preferred(for: .formula) == entry.id)
    check(PluginSecret.deleted.isEmpty)
    PluginSecret.fail = false; plugins.forget()
    check(plugins.entries.isEmpty && plugins.selection.isEmpty)
    check(PluginSecret.deleted == [entry.id])
    check(OCRPlugins(defaults: defaults).entries.isEmpty)
    let formulaOnly = OCRPluginManifest(schema: 1, id: "example.formula", name: "Formula", version: "1", executable: "baker-python", arguments: [], operations: ["formula"], timeoutSeconds: 1)
    let unsupported = OCRPlugins.Entry(manifest: formulaOnly, folder: entry.folder, digest: entry.digest)
    defaults.set(try JSONEncoder().encode([unsupported]), forKey: PreferenceKeys.ocrPlugins.name)
    defaults.removeObject(forKey: PreferenceKeys.ocrPluginPriorities.name)
    defaults.set(unsupported.id, forKey: PreferenceKeys.ocrPluginSelection.name)
    let partial = OCRPlugins(defaults: defaults)
    check(partial.preferred(for: .formula) == unsupported.id && partial.preferred(for: .markdown).isEmpty && partial.preferred(for: .latex).isEmpty)
    do { try partial.select(unsupported.id, job: .markdown); fatalError("Unsupported operation accepted") }
    catch let error as BakerError { check(error.code == .configurationInvalid) }
    let folder = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("configuration-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[2]), to: folder.appendingPathComponent("worker.py"))
    var configurable = OCRPluginManifest(schema: 1, id: "example.config", name: "Config", version: "1", executable: "baker-python", arguments: ["{plugin}/worker.py", "normal"], operations: ["formula"], timeoutSeconds: 1)
    configurable.configuration = true
    try JSONEncoder().encode(configurable).write(to: folder.appendingPathComponent("plugin.json"))
    let setupEntry = OCRPlugins.Entry(manifest: configurable, folder: folder, digest: try OCRPluginPackage.digest(folder))
    defaults.set(try JSONEncoder().encode([setupEntry]), forKey: PreferenceKeys.ocrPlugins.name)
    let configured = OCRPlugins(defaults: defaults, resources: URL(fileURLWithPath: "/Applications/Baker.app/Contents/Resources"))
    let priorReads = PluginSecret.reads
    _ = try await configured.run(setupEntry, operation: "configure")
    check(PluginSecret.reads == priorReads && configured.counts[setupEntry.id] == nil)
    let image = folder.appendingPathComponent("input.png"); try Data([1]).write(to: image)
    // The image is deliberately outside the approved package so its digest stays unchanged.
    try FileManager.default.removeItem(at: image)
    let input = folder.deletingLastPathComponent().appendingPathComponent("setup-image.png"); try Data([1]).write(to: input)
    _ = try await configured.run(setupEntry, operation: "formula", input: input)
    check(configured.counts[setupEntry.id]?.images == 1)
    _ = try await configured.run(setupEntry, operation: "configure")
    check(configured.counts[setupEntry.id]?.images == 1 && !configured.running)
    print("Plugin priorities, migration and removal: \(checks) checks passed with isolated preferences and a fake key store")
}
Task { @MainActor in do { try await registryChecks(); exit(0) } catch { print(error); exit(1) } }
dispatchMain()
