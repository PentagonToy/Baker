import CoreGraphics
import Foundation

/// Coalesce concurrent reads only. Finished images remain in the existing six-entry cache.
@MainActor
final class ThumbnailRequests {
    private struct Entry {
        let token: UUID
        let store: ObjectIdentifier
        let task: Task<CGImage, Error>
    }
    private var entries: [UUID: Entry] = [:]
    func load(_ id: UUID, store: AnyObject, operation: @escaping () async throws -> CGImage) async throws -> CGImage {
        try Task.checkCancellation()
        let storeID = ObjectIdentifier(store)
        let entry: Entry
        if let running = entries[id], running.store == storeID { entry = running }
        else {
            entries[id]?.task.cancel()
            entry = Entry(token: UUID(), store: storeID, task: Task { try Task.checkCancellation(); return try await operation() })
            entries[id] = entry
        }
        defer { if entries[id]?.token == entry.token { entries.removeValue(forKey: id) } }
        let image = try await entry.task.value
        try Task.checkCancellation()
        guard !entry.task.isCancelled else { throw CancellationError() }
        return image
    }
    func cancelAll() {
        entries.values.forEach { $0.task.cancel() }
        entries.removeAll()
    }
}
