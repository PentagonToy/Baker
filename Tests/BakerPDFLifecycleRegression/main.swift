import Foundation
import Darwin

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let python = URL(fileURLWithPath: CommandLine.arguments[2])
let worker = URL(fileURLWithPath: CommandLine.arguments[3])
let files = FileManager.default
let config = root.appendingPathComponent("config.json"), pidFile = root.appendingPathComponent("pid")
var checks = 0
func check(_ value: Bool, _ label: String) { precondition(value, label); checks += 1 }
func configure(_ mode: String) throws {
    try JSONSerialization.data(withJSONObject: ["mode": mode, "pid": pidFile.path]).write(to: config)
    try? files.removeItem(at: pidFile)
}
let engine = PDFDocumentEngine(python: python, worker: worker, configuration: config)
let source = root.appendingPathComponent("source.pdf")
try Data("authored protocol fixture".utf8).write(to: source)
for format in PDFExportFormat.allCases {
    try configure("success")
    var updates: [PDFConversionProgress] = []
    let destination = root.appendingPathComponent("result." + format.fileExtension)
    let report = try PDFDocumentWorker.convert(source: source, destination: destination, format: format, engine: engine, options: .init(), expectedPages: 1, isCancelled: { false }, progress: { updates.append($0) })
    let expected = format == .markdown ? "# Fixture\n\n$x+y$\n" : "\\[x+y\\]\n"
    check(try String(contentsOf: destination, encoding: .utf8) == expected, "Output content preserved")
    check(report.totalPages == 1 && report.pages[0].source == .structured, "Report preserved")
    check(updates.contains { $0.pageNumber == 1 && $0.phase == .recognising }, "Valid progress after partial JSON")
}
try configure("failure")
do {
    _ = try PDFDocumentWorker.convert(source: source, destination: root.appendingPathComponent("failed.md"), format: .markdown, engine: engine, options: .init(), expectedPages: 1, isCancelled: { false }, progress: { _ in })
    fatalError("Failed worker accepted")
} catch let error as BakerError {
    check(error.code == .recognitionFailed && error.diagnostic == "fixture failure", "Bounded useful failure tail")
    check(error.userDescription == "Document recognition did not complete.", "Diagnostics stay outside normal UI")
}
try configure("flood")
do {
    _ = try PDFDocumentWorker.convert(source: source, destination: root.appendingPathComponent("flood.md"), format: .markdown, engine: engine, options: .init(), expectedPages: 1, isCancelled: { false }, progress: { _ in })
    fatalError("Output flood accepted")
} catch let error as BakerError { check(error.code == .processOutputLimit, "Output limit applies even after immediate exit") }
try configure("cancel")
let start = ProcessInfo.processInfo.systemUptime
do {
    _ = try PDFDocumentWorker.convert(source: source, destination: root.appendingPathComponent("cancel.md"), format: .markdown, engine: engine, options: .init(), expectedPages: 1, isCancelled: { ProcessInfo.processInfo.systemUptime - start > 0.4 }, progress: { _ in })
    fatalError("Cancellation lost")
} catch is CancellationError { checks += 1 }
let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8))!
check(kill(pid, 0) != 0 && errno == ESRCH, "Unresponsive worker killed and reaped")
check(ProcessInfo.processInfo.systemUptime - start < 5, "Cancellation escalation stays bounded")
try configure("success")
do {
    _ = try PDFDocumentWorker.convert(source: source, destination: root.appendingPathComponent("pre-cancel.md"), format: .markdown, engine: engine, options: .init(), expectedPages: 1, isCancelled: { true }, progress: { _ in })
    fatalError("Pre-cancelled job launched")
} catch is CancellationError { check(!files.fileExists(atPath: pidFile.path), "Pre-cancel prevents launch") }
print("PDF process lifecycle:", checks, "checks passed")
