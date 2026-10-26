import Foundation
import BakerCore

extension Workbench {
    var canRecogniseFormula: Bool { plugins.selected(for: "formula") != nil || developerRuntimeOverrides || formulaSetup.ready }
    var canConvertDocument: Bool { plugins.selected(for: "pdf") != nil || preparedDocumentEngine != nil }
    func recogniseInput(_ request: RecognitionRequest, captureID: UUID? = nil) async throws -> FormulaRecognition {
        if request.formula, let plugin = plugins.selected(for: "formula") {
            if let captureID { formulaResults[captureID]?.model = plugin.manifest.modelIdentity }
            do {
                let result = try await plugins.run(plugin, operation: "formula", input: request.url)
                guard let latex = result.latex else { throw BakerError(message: "The plugin returned no formula.", code: .invalidResponse) }
                return FormulaRecognition(latex: latex, confidence: nil, model: plugin.manifest.modelIdentity)
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || BakerError.wrapping(error).code == .cancelled { throw CancellationError() }
                guard developerRuntimeOverrides || formulaSetup.ready else { throw BakerError(message: "The plugin failed. Prepare a local formula model to enable fallback.", code: .modelNotReady, recovery: .formulaSettings) }
                plugins.message = "Plugin unavailable. Trying Baker · Local for this formula."
            }
        }
        if request.formula && !developerRuntimeOverrides && !formulaSetup.ready {
            throw BakerError(message: "Prepare a formula model in Settings → Formula.", code: .modelNotReady, recovery: .formulaSettings)
        }
        if request.formula, let captureID { formulaResults[captureID]?.model = "Baker · Local" }
        let result = try await recognitionFlow.recognise(request)
        try Task.checkCancellation()
        usage.record()
        return result
    }
    func convertDocument(source: URL, destination: URL, format: PDFExportFormat, options: PDFConversionOptions,
                         progress: @escaping @MainActor (PDFConversionProgress) -> Void) async throws -> PDFConversionReport {
        if let plugin = plugins.selected(for: "pdf") {
            progress(PDFConversionProgress(pageNumber: 0, totalPages: 0, phase: .recognising, message: "Converting with " + plugin.manifest.name + "…", provider: plugin.manifest.label))
            do {
                let result = try await plugins.run(plugin, operation: "pdf", input: source, destination: destination, format: format)
                guard let report = result.report else { throw BakerError(message: "The plugin returned no document.", code: .invalidResponse) }
                return report
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || BakerError.wrapping(error).code == .cancelled { throw CancellationError() }
                guard options.documentEngine != nil else { throw BakerError(message: "The plugin failed. Prepare the Offline Model to enable PDF fallback.", code: .modelNotReady, recovery: .pdfSettings) }
                plugins.message = "Plugin unavailable. Trying Baker · Local for this PDF."
            }
        }
        guard options.documentEngine != nil else {
            throw BakerError(message: "Prepare the Offline Model in Settings → Advanced for PDF conversion.", code: .modelNotReady, recovery: .pdfSettings)
        }
        var report = try await documentFlow.convert(source: source, destination: destination, format: format, options: options) { update in
            progress(PDFConversionProgress(pageNumber: update.pageNumber, totalPages: update.totalPages, phase: update.phase, message: update.message, provider: "Baker · Local"))
        }
        report.provider = "Baker · Local"
        try Task.checkCancellation()
        usage.record(pages: report.totalPages)
        return report
    }
}
