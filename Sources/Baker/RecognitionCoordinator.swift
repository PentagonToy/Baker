import AppKit
import BakerCore

struct RecognitionRequest: Sendable {
    let url: URL
    let formula: Bool
    let python: String
    let configuration: String
    let languages: [String]
    let finnish: Bool
    let tesseract: String
}

/// Keeps worker and preview cancellation in one place, without a resident process.
@MainActor
final class RecognitionCoordinator {
    typealias Recogniser = @Sendable (RecognitionRequest) throws -> FormulaRecognition
    private let recogniseInput: Recogniser
    private let renderSource: @MainActor (String) async throws -> NSImage
    private var worker: Task<FormulaRecognition, Error>?
    private var warmup: Task<Void, Never>?
    private var preview: Task<NSImage, Error>?
    var job: Task<Void, Never>?
    var editJob: Task<Void, Never>?
    init(recogniser: @escaping Recogniser, renderer: @escaping @MainActor (String) async throws -> NSImage) {
        recogniseInput = recogniser; renderSource = renderer
    }
    func recognise(_ request: RecognitionRequest) async throws -> FormulaRecognition {
        try Task.checkCancellation()
        guard worker == nil else { throw BakerError(message: "Recognition is already running.", code: .invalidState) }
        let recogniseInput = recogniseInput
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let result = try recogniseInput(request)
            try Task.checkCancellation(); return result
        }
        worker = task
        defer { worker = nil }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }
    func render(_ source: String) async throws -> NSImage {
        try Task.checkCancellation()
        guard preview == nil else { throw BakerError(message: "A preview is already being rendered.", code: .invalidState) }
        let task = Task { try await renderSource(source) }
        preview = task
        defer { preview = nil }
        let result = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        try Task.checkCancellation(); return result
    }
    func warmText(languages: [String]) {
        guard warmup == nil else { return }
        warmup = Task.detached(priority: .utility) {
            guard !Task.isCancelled else { return }
            try? prepareTextRecognition(languages: languages)
        }
    }
    func cancel() { warmup?.cancel(); job?.cancel(); editJob?.cancel(); worker?.cancel(); preview?.cancel() }
    func close() async {
        let job = job, edit = editJob, worker = worker, preview = preview, warmup = warmup
        cancel()
        _ = await job?.result; _ = await edit?.result; _ = await worker?.result; _ = await preview?.result; _ = await warmup?.result
    }
}
