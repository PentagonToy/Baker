import CryptoKit
import Foundation
import PDFKit

/// Versioned, provider-neutral JSON over stdin/stdout. Plugins are user-installed programs, not a sandbox.
public struct OCRPluginManifest: Codable, Equatable, Sendable {
    public let schema: Int
    public let id: String
    public let name: String
    public let version: String
    public let executable: String
    public let arguments: [String]
    public let operations: [String]
    public var configuration: Bool? = nil
    public let timeoutSeconds: Int?
    enum CodingKeys: String, CodingKey { case schema, id, name, version, executable, arguments, operations, configuration; case timeoutSeconds = "timeout_seconds" }
    public var label: String { "Plugin · " + String(name.prefix(24)) + (name.count > 24 ? "…" : "") }
    public var modelIdentity: String { "plugin:" + id + "@" + version + "|" + name }
    public static func read(_ folder: URL) throws -> Self {
        let url = folder.appendingPathComponent("plugin.json")
        let info = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) <= 32_768 else { throw invalid("Choose a small, regular plugin.json file.") }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        func text(_ s: String, limit: Int) -> Bool { !s.isEmpty && s.count <= limit && !s.contains("|") && !s.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }
        guard value.schema == 1, value.id.range(of: #"^[a-z0-9][a-z0-9.-]{0,63}$"#, options: .regularExpression) != nil,
              text(value.name, limit: 64), text(value.version, limit: 32),
              value.executable == "baker-python" || value.executable.hasPrefix("/") || value.executable.hasPrefix("{plugin}/"),
              !value.executable.contains("\0"), value.arguments.count <= 24,
              value.arguments.allSatisfy({ $0.utf8.count <= 4096 && !$0.contains("\0") }),
              !value.operations.isEmpty, Set(value.operations).count == value.operations.count,
              Set(value.operations).isSubset(of: ["formula", "pdf"]), (1...7200).contains(value.timeoutSeconds ?? 120) else {
            throw invalid("The plugin manifest is invalid or uses an unsupported protocol.")
        }
        return value
    }
    static func invalid(_ message: String) -> BakerError { BakerError(message: message, code: .configurationInvalid, recovery: .advancedSettings) }
}

public enum OCRPluginPackage {
    /// Hash every executable/support file; reject links, large bundles and special files.
    public static func digest(_ folder: URL) throws -> String {
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw OCRPluginManifest.invalid("Choose a plugin folder.") }
        // Foundation enumerates /var through /private/var. Normalise both the root and entries before deriving relative paths.
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]) else { throw OCRPluginManifest.invalid("Choose a plugin folder.") }
        var names: [String] = [], total = 0, entries = 0
        for case let file as URL in iterator {
            entries += 1
            guard entries <= 256 else { throw OCRPluginManifest.invalid("Plugin packages are limited to 256 entries.") }
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            guard info.isSymbolicLink != true, info.isRegularFile == true || info.isDirectory == true else { throw OCRPluginManifest.invalid("Plugin packages cannot contain links or special files.") }
            if file.lastPathComponent == ".DS_Store" { continue }
            if info.isRegularFile == true {
                total += info.fileSize ?? 16 * 1024 * 1024 + 1
                guard total <= 16 * 1024 * 1024 else { throw OCRPluginManifest.invalid("Keep plugin code below 16 MB; store models and runtime dependencies separately.") }
                let path = file.standardizedFileURL.path
                guard path.hasPrefix(root.path + "/") else { throw OCRPluginManifest.invalid("The plugin package contains an invalid path.") }
                names.append(String(path.dropFirst(root.path.count + 1)))
            }
        }
        var hash = SHA256()
        for name in names.sorted() {
            let data = try Data(contentsOf: root.appendingPathComponent(name))
            hash.update(data: Data(name.utf8)); hash.update(data: Data([0]))
            hash.update(data: Data(String(data.count).utf8)); hash.update(data: Data([0])); hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public struct OCRPluginExecution: Sendable {
    public let latex: String?
    public let report: PDFConversionReport?
}

public enum OCRPluginRunner {
    private struct Response: Decodable {
        let schema: Int
        let id: String
        let ok: Bool
        let latex: String?
        let output: String?
        let warnings: [String]?
    }
    /// The approved package digest is checked again before every launch. No shell interpolation.
    public static func run(folder: URL, approvedDigest: String, python: URL, dataDirectory: URL,
                           operation: String, input: URL? = nil, destination: URL? = nil,
                           format: PDFExportFormat? = nil, apiKey: String? = nil, setupFile: URL? = nil) throws -> OCRPluginExecution {
        let manifest = try OCRPluginManifest.read(folder)
        guard try OCRPluginPackage.digest(folder) == approvedDigest else { throw OCRPluginManifest.invalid("This plugin changed after approval. Remove and import it again before use.") }
        guard operation == "probe" || (operation == "configure" && manifest.configuration == true) || manifest.operations.contains(operation) else { throw OCRPluginManifest.invalid("This plugin does not support the requested operation.") }
        if operation == "configure" || operation == "probe" {
            guard input == nil, destination == nil, format == nil else { throw OCRPluginManifest.invalid("Setup and connection checks cannot receive a document.") }
        }
        let files = FileManager.default
        if let input {
            let info = try input.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard info.isRegularFile == true, (info.fileSize ?? Int.max) <= 256 * 1024 * 1024 else { throw BakerError(message: "The plugin input must be a regular file below 256 MB.", code: .resourceLimit) }
        }
        var pageCount = 0
        if operation == "pdf" {
            guard let input, let destination, format != nil, !files.fileExists(atPath: destination.path),
                  let document = PDFDocument(url: input), (1...2000).contains(document.pageCount) else {
                throw OCRPluginManifest.invalid("Choose a valid PDF and an unused export destination.")
            }
            pageCount = document.pageCount
        } else if operation == "formula", input == nil { throw OCRPluginManifest.invalid("Choose a formula image.") }
        let job = files.temporaryDirectory.appendingPathComponent("baker-plugin-" + UUID().uuidString)
        let output = job.appendingPathComponent("output")
        try files.createDirectory(at: output, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: job) }
        try files.createDirectory(at: dataDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let id = UUID().uuidString
        var request: [String: Any] = ["schema": 1, "id": id, "operation": operation]
        if let input { request["input"] = ["path": input.path] }
        if operation == "pdf", let format { request["output"] = ["directory": output.path, "format": format.rawValue] }
        let replace: (String) -> String = { $0.replacingOccurrences(of: "{plugin}", with: folder.path) }
        let executable = manifest.executable == "baker-python" ? python : URL(fileURLWithPath: replace(manifest.executable))
        guard files.isExecutableFile(atPath: executable.path) else { throw OCRPluginManifest.invalid("The plugin executable is unavailable.") }
        let arguments = (manifest.executable == "baker-python" ? ["-I", "-B"] : []) + manifest.arguments.map(replace)
        var environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin", "HOME": NSHomeDirectory(),
                           "TMPDIR": NSTemporaryDirectory(), "LANG": "en_US.UTF-8",
                           "BAKER_PLUGIN_DATA": dataDirectory.path, "BAKER_PLUGIN_DIR": folder.path]
        environment["BAKER_PLUGIN_API_KEY"] = apiKey ?? ""
        if operation == "configure", let setupFile { environment["BAKER_PLUGIN_SETUP_FILE"] = setupFile.path }
        let result = try runProcess(executable, arguments: arguments,
            timeout: operation == "probe" ? 10 : operation == "configure" ? 360 : min(Double(manifest.timeoutSeconds ?? 120), operation == "formula" ? 120 : 7200),
            input: try JSONSerialization.data(withJSONObject: request),
            environment: environment, maximumOutputBytes: 256 * 1024, inheritEnvironment: false)
        // Provider diagnostics can contain credentials. Do not echo stderr or untrusted error bodies.
        guard result.status == 0, let response = try? JSONDecoder().decode(Response.self, from: result.output),
              response.schema == 1, response.id == id, response.ok else {
            throw BakerError(message: "\(manifest.name) did not return a valid result. Check its settings or choose Local.", code: .invalidResponse, recovery: .advancedSettings)
        }
        if operation == "probe" || operation == "configure" { return OCRPluginExecution(latex: nil, report: nil) }
        if operation == "formula" {
            guard let latex = response.latex, !latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  latex.count <= 8000, latex.utf8.count <= 32_768 else { throw BakerError(message: "The plugin returned an empty or oversized formula.", code: .invalidResponse) }
            return OCRPluginExecution(latex: latex, report: nil)
        }
        guard let destination, let format, let name = response.output,
              name == "result." + format.fileExtension, !files.fileExists(atPath: destination.path) else {
            throw BakerError(message: "The plugin returned an invalid document destination or input PDF.", code: .invalidResponse)
        }
        try validateOutput(output)
        let source = output.appendingPathComponent(name)
        let info = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard info.isRegularFile == true, (info.fileSize ?? Int.max) <= 64 * 1024 * 1024 else { throw BakerError(message: "The plugin document is missing or exceeds 64 MB.", code: .resourceLimit) }
        try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PDFExportBundle.save(source: source, destination: destination)
        let pages = (1...pageCount).map { PDFPageSummary(pageNumber: $0, source: .structured, blockCount: 0, characterCount: 0, warnings: []) }
        let warnings = Array((response.warnings ?? []).prefix(16)).map { String($0.prefix(300)) }
        let report = PDFConversionReport(destination: destination, format: format, pages: pages,
            bytesWritten: try Data(contentsOf: destination).count, warnings: warnings, provider: manifest.label)
        return OCRPluginExecution(latex: nil, report: report)
    }
    private static func validateOutput(_ folder: URL) throws {
        guard let iterator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]) else { throw BakerError(message: "The plugin output folder is unavailable.", code: .invalidResponse) }
        var count = 0, bytes = 0
        for case let file as URL in iterator {
            count += 1
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            bytes += info.fileSize ?? 0
            guard count <= 1000, bytes <= 512 * 1024 * 1024, info.isSymbolicLink != true,
                  info.isRegularFile == true || info.isDirectory == true else { throw BakerError(message: "The plugin output contains links, special files or excessive data.", code: .invalidResponse) }
        }
    }
}
