import Darwin
import Foundation

public struct PDFDocumentEngine: Sendable {
    public let python: URL
    public let worker: URL
    public let configuration: URL
    public init(python: URL, worker: URL, configuration: URL) {
        self.python = python; self.worker = worker; self.configuration = configuration
    }
}

enum PDFDocumentWorker {
    struct State: Decodable { let page: Int; let total: Int; let phase: String? }
    struct Report: Decodable {
        struct Page: Decodable { let page: Int; let attached_labels: Int; let unmatched_labels: [String]; let block_count: Int?; let character_count: Int? }
        let pages: [Page]
        let warnings: [String]
    }
    static func convert(source: URL, destination: URL, format: PDFExportFormat, engine: PDFDocumentEngine, options: PDFConversionOptions, expectedPages: Int,
                        isCancelled: @Sendable () -> Bool, progress: @Sendable (PDFConversionProgress) -> Void) throws -> PDFConversionReport {
        if isCancelled() { throw CancellationError() }
        let files = FileManager.default
        guard files.isExecutableFile(atPath: engine.python.path), files.fileExists(atPath: engine.worker.path), files.fileExists(atPath: engine.configuration.path) else {
            throw BakerError(message: "The document recognition engine is incomplete. Prepare the local document models first.", code: .modelNotReady, recovery: .pdfSettings)
        }
        let job = files.temporaryDirectory.appendingPathComponent("baker-pdf-job-" + UUID().uuidString)
        try files.createDirectory(at: job, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? files.removeItem(at: job) }
        let output = job.appendingPathComponent("output"), log = job.appendingPathComponent("worker.log")
        files.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log); defer { try? handle.close() }
        let process = Process()
        let completion = ProcessCompletion(process)
        process.executableURL = engine.python
        process.arguments = ["-I", "-B", engine.worker.path, "--source", source.path, "--output", output.path, "--config", engine.configuration.path]
        process.standardOutput = handle; process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        do { try process.run() }
        catch { throw BakerError(message: "The document recognition process could not start.", code: .processLaunchFailed, diagnostic: error.localizedDescription, recovery: .pdfSettings) }
        defer { completion.stopAndWait() }
        let deadline = ProcessInfo.processInfo.systemUptime + 7_200
        func checkLogLimit() throws {
            if let size = try files.attributesOfItem(atPath: log.path)[.size] as? NSNumber, size.intValue > 8 * 1_024 * 1_024 {
                throw BakerError(message: "The document engine produced too much diagnostic output.", code: .processOutputLimit)
            }
        }
        func readProgress() -> State? {
            guard let reader = try? FileHandle(forReadingFrom: output.appendingPathComponent("progress.json")) else { return nil }
            defer { try? reader.close() }
            guard let data = try? reader.read(upToCount: 16_385), data.count <= 16_384 else { return nil }
            return try? JSONDecoder().decode(State.self, from: data)
        }
        var nextProgressRead = 0.0
        var lastState = ""
        while true {
            if isCancelled() { throw CancellationError() }
            let now = ProcessInfo.processInfo.systemUptime
            guard now < deadline else { throw BakerError(message: "Document recognition exceeded its time limit. Convert a smaller PDF.", code: .processTimedOut) }
            try checkLogLimit()
            if now >= nextProgressRead {
                nextProgressRead = now + 0.25
                if let state = readProgress(), state.total == expectedPages, (0...expectedPages).contains(state.page) {
                    let key = "\(state.page):\(state.phase ?? "completed")"
                    if key != lastState {
                        lastState = key
                        let phase: PDFConversionProgress.Phase
                        let message: String
                        switch state.phase {
                        case "preparing": phase = .preparing; message = "Preparing local document models…"
                        case "recognising": phase = .recognising; message = "Recognising page \(state.page) of \(state.total)"
                        case "finalising": phase = .finalising; message = "Finishing document export…"
                        default: phase = .completed; message = "Recognised page \(state.page) of \(state.total)"
                        }
                        progress(.init(pageNumber: state.page, totalPages: state.total, phase: phase, message: message))
                    }
                }
            }
            if completion.wait(for: min(0.1, max(0, deadline - ProcessInfo.processInfo.systemUptime))) { break }
        }
        process.waitUntilExit()
        if isCancelled() { throw CancellationError() }
        try checkLogLimit()
        guard process.terminationStatus == 0 else {
            let detail = processDiagnosticTail(log) ?? "Unknown recognition error"
            throw BakerError(message: "Document recognition did not complete.", code: .recognitionFailed, diagnostic: String(detail.suffix(500)))
        }
        let report = try JSONDecoder().decode(Report.self, from: Data(contentsOf: output.appendingPathComponent("report.json")))
        guard report.pages.map(\.page) == Array(1...expectedPages), report.pages.count <= options.maximumPages,
              report.pages.allSatisfy({ ($0.character_count ?? 0) <= options.maximumPageCharacters }) else { throw BakerError(message: "The document engine returned an invalid page count.", code: .invalidResponse) }
        let result = output.appendingPathComponent("document." + format.fileExtension)
        let bytes = try files.attributesOfItem(atPath: result.path)[.size] as? NSNumber
        guard let bytes, bytes.intValue <= options.maximumOutputBytes else { throw BakerError(message: "The recognised document exceeds the output size limit.", code: .resourceLimit) }
        try PDFExportBundle.save(source: result, destination: destination)
        let summaries = report.pages.map { page in
            PDFPageSummary(pageNumber: page.page, source: .structured, blockCount: page.block_count ?? 0, characterCount: page.character_count ?? 0,
                           warnings: page.unmatched_labels.isEmpty ? [] : ["Some equation labels need review: " + page.unmatched_labels.joined(separator: ", ")])
        }
        let savedBytes = try files.attributesOfItem(atPath: destination.path)[.size] as? NSNumber
        guard let savedBytes else { throw BakerError(message: "The saved document size could not be read.", code: .storageFailed) }
        return PDFConversionReport(destination: destination, format: format, pages: summaries, bytesWritten: savedBytes.intValue,
                                   warnings: report.warnings + summaries.flatMap(\.warnings))
    }
}
