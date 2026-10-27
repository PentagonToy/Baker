import AppKit
import BakerCore

/// Prepares images off the main actor and never overwrites a newer clipboard request.
@MainActor
final class ClipboardCoordinator {
    let pasteboard: NSPasteboard
    private var generation = 0
    private var worker: Task<ImageClipboard.Payload, Error>?
    private var workerToken: UUID?
    private let prepareImage: @Sendable (URL) throws -> ImageClipboard.Payload
    init(pasteboard: NSPasteboard, prepareImage: @escaping @Sendable (URL) throws -> ImageClipboard.Payload = { try ImageClipboard.prepare(imageURL: $0) }) {
        self.pasteboard = pasteboard; self.prepareImage = prepareImage
    }
    var isPreparingImage: Bool { worker != nil }
    func close() async {
        let pending = worker, token = workerToken
        invalidate(); _ = await pending?.result
        if workerToken == token { worker = nil; workerToken = nil }
    }
    func invalidate() { generation &+= 1; worker?.cancel() }
    func copyImage(_ url: URL) async throws -> Bool {
        invalidate()
        let request = generation, previous = pasteboard.changeCount
        let prepare = prepareImage
        let previousWorker = worker
        _ = await previousWorker?.result
        try Task.checkCancellation()
        guard request == generation else { return false }
        let token = UUID()
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let payload = try prepare(url)
            try Task.checkCancellation()
            return payload
        }
        worker = task; workerToken = token
        defer { if workerToken == token { worker = nil; workerToken = nil } }
        let payload: ImageClipboard.Payload
        do { payload = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() }) }
        catch is CancellationError {
            if request != generation { return false }
            throw CancellationError()
        }
        try Task.checkCancellation()
        guard request == generation, pasteboard.changeCount == previous else { return false }
        try ImageClipboard.write(payload, to: pasteboard); return true
    }
    func copyText(_ text: String) throws {
        invalidate(); pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { throw BakerError(message: "The text could not be copied.", code: .clipboardFailed) }
    }
    func copyMath(_ text: String, font: MathFont) throws {
        invalidate()
        let item = try MathClipboard.item(text: text, font: font)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw BakerError(message: "The formula could not be copied.", code: .clipboardFailed) }
    }
    func copyFiles(_ files: [URL]) throws {
        invalidate(); pasteboard.clearContents()
        guard pasteboard.writeObjects(files.map { $0 as NSURL }) else { throw BakerError(message: "The file was saved, but could not be copied.", code: .clipboardFailed) }
    }
}
