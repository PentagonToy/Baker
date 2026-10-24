import Foundation
import BakerCore

extension Workbench {
    var canRecogniseFormula: Bool { mathpix.available || developerRuntimeOverrides || formulaSetup.ready }
    var canConvertDocument: Bool { mathpix.available || preparedDocumentEngine != nil }
    func recogniseUsingProvider(_ request: RecognitionRequest) async throws -> FormulaRecognition {
        if request.formula && mathpix.available {
            do {
                let result = try await mathpix.client.recognise(request.url)
                try Task.checkCancellation(); mathpix.record(online: true, pages: nil)
                mathpix.message = "Last formula recognised with Mathpix."
                return result
            } catch is CancellationError { throw CancellationError() }
            catch {
                mathpix.failed(error)
                guard MathpixConnection.connectionFailure(error) else { throw error }
                mathpix.message = "Mathpix could not connect. Using Baker on this Mac."
            }
        } else if request.formula && mathpix.preferred {
            mathpix.message = "Offline. Using Baker on this Mac."
        }
        if request.formula && !developerRuntimeOverrides && !formulaSetup.ready {
            throw BakerError(message: "Prepare a local formula model in Settings → Formula to use Baker offline.", code: .modelNotReady, recovery: .formulaSettings)
        }
        let result = try await recognitionFlow.recognise(request)
        try Task.checkCancellation(); mathpix.record(online: false, pages: nil)
        return result
    }
    func convertDocument(source: URL, destination: URL, format: PDFExportFormat, options: PDFConversionOptions,
                         progress: @escaping @MainActor (PDFConversionProgress) -> Void) async throws -> PDFConversionReport {
        if mathpix.available {
            do {
                let report = try await mathpix.client.convert(source: source, destination: destination, format: format) { completed, total, message in
                    await progress(PDFConversionProgress(pageNumber: min(total, completed + 1), totalPages: total, phase: completed >= total ? .completed : .recognising, message: message))
                }
                try Task.checkCancellation(); mathpix.record(online: true, pages: report.totalPages)
                mathpix.message = "Last PDF converted with Mathpix."
                return report
            } catch is CancellationError { throw CancellationError() }
            catch {
                mathpix.failed(error)
                guard MathpixConnection.connectionFailure(error) else { throw error }
                mathpix.message = "Mathpix could not connect. Using Baker on this Mac."
                progress(PDFConversionProgress(pageNumber: 0, totalPages: 0, phase: .preparing, message: "Mathpix unavailable. Preparing local conversion…"))
            }
        } else if mathpix.preferred { mathpix.message = "Offline. Using Baker on this Mac." }
        guard options.documentEngine != nil else { throw BakerError(message: "Prepare the Offline Model in Settings → Advanced for PDF conversion without Mathpix.", code: .modelNotReady, recovery: .pdfSettings) }
        let report = try await documentFlow.convert(source: source, destination: destination, format: format, options: options, progress: progress)
        try Task.checkCancellation(); mathpix.record(online: false, pages: report.totalPages)
        return report
    }
}
