import Foundation
import BakerCore

enum BakerAutomation {
    struct Request: Codable {
        var id = UUID()
        var issuedAt = Date()
        let operation: String
        var path: String?
        var output: String?
        var text: String?
        var format: String?
        var limit: Int?
        var offset: Int?
    }
    static var directory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Baker/Automation") }
    static let commands = ["plugins", "plugin-use", "plugin-probe", "status", "diagnostics", "history", "formulas", "copy-formula", "result", "capture", "record", "stop", "cancel", "import", "open-formula", "copy", "settings", "clear-cache", "pdf"]
    static func emit(_ value: [String: Any]) -> Int32 {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
        FileHandle.standardOutput.write(data + Data("\n".utf8))
        return value["ok"] as? Bool == false ? 1 : 0
    }
}

enum BakerCLI {
    static func run(_ arguments: [String]) -> Int32? {
        guard arguments.first == "--cli" else { return nil }
        let args = Array(arguments.dropFirst()), command = args.first ?? "help"
        do {
            if command == "help" { return BakerAutomation.emit(["ok": true, "version": 1, "commands": BakerAutomation.commands + ["version", "unicode", "formula", "request"], "syntax": "baker COMMAND [PATH] [--format VALUE] [--text TEXT] [--output PATH] [--limit N] [--offset N] [--timeout SECONDS]", "captureFormats": ["area", "all", "window", "repeat", "scroll", "text", "formula"], "recordFormats": ["video", "gif"], "notes": "Live commands require Baker running. Capture/record return accepted; poll status/result. Formula and Unicode run headlessly."]) }
            if command == "version" { return BakerAutomation.emit(["ok": true, "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development"]) }
            func option(_ key: String) -> String? { guard let i = args.firstIndex(of: key), args.indices.contains(i+1) else { return nil }; return args[i+1] }
            if command == "unicode" { let value = UnicodeMath.approximate(option("--text") ?? args.dropFirst().first ?? ""); return BakerAutomation.emit(["ok": true, "text": value.text, "warnings": value.warnings, "available": !value.text.isEmpty]) }
            if command == "formula" {
                guard let path = args.dropFirst().first, path.hasPrefix("/") else { throw FormulaAdapter.Failure(message: "Provide an absolute image path.") }
                let data = try JSONSerialization.data(withJSONObject: ["version": 1,"id": UUID().uuidString,"operation": "formula","image": path])
                let response = try runProcess(Bundle.main.executableURL!, arguments: ["--adapter"], timeout: 180, input: data)
                FileHandle.standardOutput.write(response.output); return response.status
            }
            let request: BakerAutomation.Request
            if command == "request" {
                let data = try FileHandle.standardInput.read(upToCount: 65537) ?? Data()
                guard data.count <= 65536 else { throw FormulaAdapter.Failure(message: "Request exceeds 64 KiB.") }
                var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                object["id"] = UUID().uuidString
                object["issuedAt"] = Date().timeIntervalSinceReferenceDate
                request = try JSONDecoder().decode(BakerAutomation.Request.self, from: JSONSerialization.data(withJSONObject: object))
            } else {
                guard BakerAutomation.commands.contains(command) else { throw FormulaAdapter.Failure(message: "Unknown command. Run baker help.") }
                request = BakerAutomation.Request(operation: command, path: args.count > 1 && !args[1].hasPrefix("--") ? args[1] : nil, output: option("--output"), text: option("--text"), format: option("--format"), limit: option("--limit").flatMap(Int.init), offset: option("--offset").flatMap(Int.init))
            }
            let folder = BakerAutomation.directory
            guard FileManager.default.fileExists(atPath: folder.path) else { throw FormulaAdapter.Failure(message: "Open Baker before using live commands.") }
            let input = folder.appendingPathComponent(request.id.uuidString + ".request.json"), output = folder.appendingPathComponent(request.id.uuidString + ".response.json")
            guard !FileManager.default.fileExists(atPath: input.path), !FileManager.default.fileExists(atPath: output.path) else { throw FormulaAdapter.Failure(message: "Request ID is already in use.") }
            let bytes = try JSONEncoder().encode(request)
            guard bytes.count <= 65536 else { throw FormulaAdapter.Failure(message: "Request exceeds 64 KiB.") }
            // The watcher must not consume the request before its permissions are set.
            let staging = folder.appendingPathComponent("." + request.id.uuidString + ".request.tmp")
            defer { try? FileManager.default.removeItem(at: staging) }
            try bytes.write(to: staging, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
            try FileManager.default.moveItem(at: staging, to: input)
            defer { try? FileManager.default.removeItem(at: input); try? FileManager.default.removeItem(at: output) }
            let deadline = Date().addingTimeInterval(min(7200, max(1, Double(option("--timeout") ?? "30") ?? 30)))
            while Date() < deadline {
                if FileManager.default.fileExists(atPath: output.path) {
                    let value = try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any] ?? [:]
                    return BakerAutomation.emit(value)
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            throw FormulaAdapter.Failure(message: "Timed out waiting for Baker. An accepted operation may still be running; inspect status before retrying.")
        } catch { return BakerAutomation.emit(["ok": false,"error": error.localizedDescription]) }
    }
}
