import CryptoKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
Task { @MainActor in
    do {
        var checks = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
        let files = FileManager.default
        let root = output.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let domain = "Baker.FormulaEngines." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = BakerPreferences(defaults: defaults)
        check(preferences[PreferenceKeys.formulaEngine] == "mfr", "Existing users retain MFR")
        let setup = FormulaSetup(runtime: root.appendingPathComponent("absent-runtime"), root: root, preferences: preferences)
        while setup.working { await Task.yield() }
        setup.select(.texo)
        while setup.working { await Task.yield() }
        check(setup.engine == .texo && preferences[PreferenceKeys.formulaEngine] == "texo", "Selection persists")
        check(!setup.ready && setup.directory.lastPathComponent == "texo-transfer-v1", "Selection clears readiness and isolates models")
        check(FormulaEngine.mfr.directoryName(variant: "mlp-int8-v1") == "mfr-1.5-mlp-int8-v1", "MFR variant remains stable")
        check(FormulaEngine.cachedMFRVariant(root: root) == nil, "Fresh installs use downloadable MFR")
        let legacy = root.appendingPathComponent("mfr-1.5-mlp-int8-v1")
        try files.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacy.appendingPathComponent("baker-config.json"))
        check(FormulaEngine.cachedMFRVariant(root: root) == "mlp-int8-v1", "Reuse previously installed optimised MFR")
        let canonical = root.appendingPathComponent("mfr-1.5")
        try files.createDirectory(at: canonical, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: canonical.appendingPathComponent("baker-config.json"))
        check(FormulaEngine.cachedMFRVariant(root: root) == "fp32", "A completed current download takes precedence")
        try files.removeItem(at: canonical)
        try files.removeItem(at: legacy)
        check(FormulaEngine.cachedMFRVariant(root: root) == nil, "Removing legacy model restores downloadable selection")
        check(FormulaEngine.allCases.count == 3, "Three formula engines are selectable")
        check(FormulaEngine.texo.title == "Texo", "Texo is a regular supported choice")
        setup.select(.plusS)
        while setup.working { await Task.yield() }
        check(preferences[PreferenceKeys.formulaEngine] == "plus-s", "plus-S selection persists")
        check(setup.directory.lastPathComponent == "pp-formulanet-plus-s-fp32-v1", "plus-S has its own cache")
        check(FormulaEngine.plusS.settings(directory: setup.directory)["max_new_tokens"] as? Int == 1024, "plus-S retains its graph limit")
        check(FormulaEngine.plusS.bundledPaths.isEmpty, "plus-S remains an optional download")
        setup.select(.texo)
        while setup.working { await Task.yield() }
        let source = root.appendingPathComponent("source")
        try files.createDirectory(at: source, withIntermediateDirectories: true)
        let data = Data("authored installation fixture".utf8)
        try data.write(to: source.appendingPathComponent("encoder_model.onnx"))
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let manifest = FormulaModelManifest(repository: "test/model", revision: "pinned", files: ["encoder_model.onnx": .init(bytes: data.count, sha256: hash)])
        let destination = setup.directory
        try FormulaSetup.provisionBundledModel(source, directory: destination, manifest: manifest, engine: .texo)
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: destination.appendingPathComponent("baker-config.json"))) as! [String: Any]
        check(config["engine"] as? String == "texo", "Provisioned configuration selects Texo")
        check(config["max_new_tokens"] as? Int == 512, "Texo decode limit is explicit")
        check(config["model_dir"] as? String == destination.path, "Configuration targets final location")
        try Data("corrupt".utf8).write(to: source.appendingPathComponent("encoder_model.onnx"))
        do {
            try FormulaSetup.provisionBundledModel(source, directory: destination, manifest: manifest, engine: .texo)
            preconditionFailure("Corrupt repair must fail")
        } catch { checks += 1 }
        check(try Data(contentsOf: destination.appendingPathComponent("encoder_model.onnx")) == data, "Failed repair preserves previous model")
        let mfr = root.appendingPathComponent("mfr-1.5")
        try files.createDirectory(at: mfr, withIntermediateDirectories: true)
        setup.remove()
        check(!files.fileExists(atPath: destination.path), "Remove affects selected Texo model")
        check(files.fileExists(atPath: mfr.path), "MFR rollback files are retained")
        setup.select(.mfr)
        while setup.working { await Task.yield() }
        check(setup.engine == .mfr && preferences[PreferenceKeys.formulaEngine] == "mfr", "Rollback persists")
        print("Passed \(checks) engine selection, provisioning and rollback checks")
        exit(0)
    } catch { print(error); exit(1) }
}
RunLoop.main.run()
