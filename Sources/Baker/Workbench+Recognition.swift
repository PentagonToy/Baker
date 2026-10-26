import Foundation
import BakerCore

extension Workbench {
    var canRecogniseFormula: Bool { developerRuntimeOverrides || formulaSetup.ready }
    var canConvertDocument: Bool { preparedDocumentEngine != nil }
    func recogniseLocally(_ request: RecognitionRequest, captureID: UUID? = nil) async throws -> FormulaRecognition {
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
