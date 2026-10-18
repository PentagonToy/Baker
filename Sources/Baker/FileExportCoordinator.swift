import Foundation
import BakerCore

/// File staging and copying run away from the interface thread, including PDF asset bundles.
@MainActor
final class FileExportCoordinator {
    private var worker: Task<Void, Error>?
    func save(source: URL, destination: URL) async throws {
        guard worker == nil else { throw BakerError(message: "Another file is being saved.", code: .invalidState) }
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            guard source.isFileURL, destination.isFileURL, source.standardizedFileURL != destination.standardizedFileURL else {
                throw BakerError(message: "Choose a different local destination.", code: .invalidInput)
            }
            if ["md", "tex"].contains(source.pathExtension.lowercased()) {
                try PDFExportBundle.save(source: source, destination: destination)
            } else {
                let files = FileManager.default
                let stage = destination.deletingLastPathComponent().appendingPathComponent(".baker-save-" + UUID().uuidString)
                defer { try? files.removeItem(at: stage) }
                try files.copyItem(at: source, to: stage)
                try Task.checkCancellation()
                if files.fileExists(atPath: destination.path) { _ = try files.replaceItemAt(destination, withItemAt: stage) }
                else { try files.moveItem(at: stage, to: destination) }
            }
        }
        worker = task
        defer { worker = nil }
        try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }
    func cancel() { worker?.cancel() }
    func close() async { let worker = worker; cancel(); _ = await worker?.result }
}
