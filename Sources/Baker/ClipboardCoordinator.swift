import AppKit
import BakerCore

/// Prepares images off the main actor and never overwrites a newer clipboard request.
@MainActor
final class ClipboardCoordinator {
    let pasteboard: NSPasteboard
    private var generation = 0
    private let prepareImage: @Sendable (URL) throws -> ImageClipboard.Payload
    init(pasteboard: NSPasteboard, prepareImage: @escaping @Sendable (URL) throws -> ImageClipboard.Payload = { try ImageClipboard.prepare(imageURL: $0) }) {
        self.pasteboard = pasteboard; self.prepareImage = prepareImage
    }
    func invalidate() { generation &+= 1 }
    func copyImage(_ url: URL) async throws -> Bool {
        invalidate()
        let request = generation, previous = pasteboard.changeCount
        let prepare = prepareImage
        let payload = try await Task.detached(priority: .userInitiated) { try prepare(url) }.value
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
