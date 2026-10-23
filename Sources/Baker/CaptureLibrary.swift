import AppKit
import BakerCore

/// Owns disk access, the bounded thumbnail cache and the serial history-write queue.
@MainActor
final class CaptureLibrary {
    enum HistoryChange { case save(SavedFormula, limit: Int, days: Int), retain(limit: Int, days: Int), clear }
    private(set) var store: CaptureStore
    private var cache: [UUID: NSImage] = [:]
    private let requests = ThumbnailRequests()
    private var historyTask: Task<[UUID: SavedFormula], Error>?
    init(directory: URL) { store = CaptureStore(directory: directory) }
    var cachedThumbnailCount: Int { cache.count }
    var pendingThumbnailCount: Int { requests.pendingCount }
    func cachedThumbnail(_ id: UUID) -> NSImage? { cache[id] }
    func thumbnail(_ record: CaptureRecord, protecting protected: Set<UUID>) async throws -> NSImage {
        if let image = cache[record.id] { return image }
        let source = store
        let raster = try await requests.load(record.id, store: source) { try await source.thumbnail(record) }
        try Task.checkCancellation()
        guard store === source else { throw CancellationError() }
        if let image = cache[record.id] { return image }
        if cache.count >= 6, let victim = cache.keys.first(where: { !protected.contains($0) }) { cache.removeValue(forKey: victim) }
        let image = NSImage(cgImage: raster, size: .zero); cache[record.id] = image; return image
    }
    func remember(_ stored: StoredCapture, records: [CaptureRecord]) {
        cache = cache.filter { id, _ in records.prefix(5).contains { $0.id == id } }
        cache[stored.record.id] = NSImage(cgImage: stored.thumbnail, size: .zero)
    }
    func clearCache() { requests.cancelAll(); cache = [:] }
    func use(_ store: CaptureStore) { clearCache(); self.store = store }
    func enqueue(_ change: HistoryChange) -> Task<[UUID: SavedFormula], Error> {
        let previous = historyTask, source = store
        let next = Task {
            _ = await previous?.result
            switch change {
            case .save(let value, let limit, let days):
                try await source.saveFormula(value)
                return try await source.maintainFormulas(limit: limit, days: days)
            case .retain(let limit, let days): return try await source.maintainFormulas(limit: limit, days: days)
            case .clear: try await source.clearFormulas(); return [:]
            }
        }
        historyTask = next; return next
    }
    func flushHistory() async { _ = await historyTask?.result }
    func cancelThumbnails() { requests.cancelAll() }
}
