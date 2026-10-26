let root = URL(fileURLWithPath: CommandLine.arguments[1])
let python = URL(fileURLWithPath: CommandLine.arguments[2])
let fixture = URL(fileURLWithPath: CommandLine.arguments[3])
let package = root.appendingPathComponent("package")
let files = FileManager.default
try files.createDirectory(at: package, withIntermediateDirectories: true)
try files.copyItem(at: fixture, to: package.appendingPathComponent("worker.py"))
let image = root.appendingPathComponent("input.png")
try Data([1, 2, 3]).write(to: image)
let pdf = root.appendingPathComponent("input.pdf")
var box = CGRect(x: 0, y: 0, width: 100, height: 100)
let context = CGContext(pdf as CFURL, mediaBox: &box, nil)!
context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()
var checks = 0
func check(_ condition: Bool) { precondition(condition); checks += 1 }
func rejected(_ body: () throws -> Void) {
    do { try body(); fatalError("Expected rejection") } catch { checks += 1 }
}
func manifest(_ mode: String = "normal", operation: [String] = ["formula", "pdf"]) throws {
    let value: [String: Any] = ["schema": 1, "id": "example.test", "name": "Test OCR", "version": "1.0.0",
        "executable": "baker-python", "arguments": ["{plugin}/worker.py", mode], "operations": operation, "timeout_seconds": 1]
    try JSONSerialization.data(withJSONObject: value).write(to: package.appendingPathComponent("plugin.json"))
}
func run(_ operation: String, mode: String = "normal", destination: URL? = nil, key: String? = nil) throws -> OCRPluginExecution {
    try manifest(mode)
    return try OCRPluginRunner.run(folder: package, approvedDigest: OCRPluginPackage.digest(package), python: python,
        dataDirectory: root.appendingPathComponent("state"), operation: operation, input: operation == "pdf" ? pdf : operation == "formula" ? image : nil,
        destination: destination, format: operation == "pdf" ? .markdown : nil, apiKey: key)
}
check(try run("probe").latex == nil)
check(try run("formula").latex == "x^2+1=0")
check(try run("formula", mode: "key", key: "synthetic-test-key").latex != nil)
for mode in ["wrong-id", "empty", "oversize", "failure", "timeout"] { rejected { _ = try run("formula", mode: mode) } }
try manifest(); let approved = try OCRPluginPackage.digest(package)
try Data("# changed".utf8).write(to: package.appendingPathComponent("extra.py"))
rejected { _ = try OCRPluginRunner.run(folder: package, approvedDigest: approved, python: python, dataDirectory: root, operation: "probe") }
try files.removeItem(at: package.appendingPathComponent("extra.py"))
try files.createSymbolicLink(at: package.appendingPathComponent("link"), withDestinationURL: fixture)
rejected { _ = try OCRPluginPackage.digest(package) }
try files.removeItem(at: package.appendingPathComponent("link"))
try manifest(operation: ["unsupported"]); rejected { _ = try OCRPluginManifest.read(package) }
let destination = root.appendingPathComponent("export.md")
check(try run("pdf", destination: destination).report?.totalPages == 1)
check(try String(contentsOf: destination).contains("baker-assets-"))
rejected { _ = try run("pdf", destination: destination) }
check(try String(contentsOf: destination).contains("# Test"))
let rejectedOutput = root.appendingPathComponent("unsafe.md")
rejected { _ = try run("pdf", mode: "symlink-output", destination: rejectedOutput) }
check(!files.fileExists(atPath: rejectedOutput.path))
print("Plugin protocol: \(checks) checks passed")
