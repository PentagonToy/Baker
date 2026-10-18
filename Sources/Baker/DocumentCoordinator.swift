import Foundation
import BakerCore

/// One conversion owner is shared by the PDF command and the file inbox.
@MainActor
final class DocumentCoordinator {
    typealias Converter = @Sendable (URL, URL, PDFExportFormat, PDFConversionOptions, @Sendable (PDFConversionProgress) -> Void) throws -> PDFConversionReport
    private let converter: Converter
    private var worker: Task<PDFConversionReport, Error>?
    private var token: UUID?
    var job: Task<Void, Never>?
    init(converter: @escaping Converter = { source, destination, format, options, progress in
        try PDFConverter.convert(source: source, destination: destination, format: format, options: options,
                                 isCancelled: { Task.isCancelled }, progress: progress)
    }) { self.converter = converter }
    func convert(source: URL, destination: URL, format: PDFExportFormat, options: PDFConversionOptions,
                 progress: @escaping @MainActor (PDFConversionProgress) -> Void) async throws -> PDFConversionReport {
        try Task.checkCancellation()
        guard worker == nil else { throw BakerError(message: "Another document is being converted.", code: .invalidState) }
        let id = UUID(), converter = converter
        token = id
        let task = Task.detached {
            try Task.checkCancellation()
            return try converter(source, destination, format, options) { value in
                Task { @MainActor [weak self] in if self?.token == id { progress(value) } }
            }
        }
        worker = task
        defer { token = nil; worker = nil }
        let result = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        try Task.checkCancellation(); return result
    }
    func cancel() { job?.cancel(); worker?.cancel(); token = nil }
    func close() async {
        let job = job, worker = worker
        cancel(); _ = await job?.result; _ = await worker?.result
    }
}
