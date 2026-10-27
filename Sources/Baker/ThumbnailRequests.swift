import CoreGraphics
import Foundation

/// Share one decode per capture, cancelling it when its last visible consumer leaves.
@MainActor
final class ThumbnailRequests {
    private struct Entry {
        let token: UUID
        let store: ObjectIdentifier
        var task: Task<Void, Never>?
        var waiters: [UUID: CheckedContinuation<CGImage, Error>]
    }
    private var entries: [UUID: Entry] = [:]
    var pendingCount: Int { entries.count }
    func load(_ id: UUID, store: AnyObject, operation: @escaping () async throws -> CGImage) async throws -> CGImage {
        try Task.checkCancellation()
        let waiter = UUID(), storeID = ObjectIdentifier(store)
        let image: CGImage = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                if entries[id]?.store == storeID {
                    entries[id]?.waiters[waiter] = continuation
                    return
                }
                remove(id)
                let token = UUID()
                entries[id] = Entry(token: token, store: storeID, task: nil, waiters: [waiter: continuation])
                entries[id]?.task = Task { [weak self] in
                    let result: Result<CGImage, Error>
                    do { try Task.checkCancellation(); let image = try await operation(); try Task.checkCancellation(); result = .success(image) }
                    catch { result = .failure(error) }
                    self?.finish(id, token: token, result: result)
                }
            }
        }, onCancel: { Task { @MainActor [weak self] in self?.cancel(id, waiter: waiter) } })
        try Task.checkCancellation()
        return image
    }
    private func finish(_ id: UUID, token: UUID, result: Result<CGImage, Error>) {
        guard entries[id]?.token == token, let entry = entries.removeValue(forKey: id) else { return }
        entry.waiters.values.forEach { $0.resume(with: result) }
    }
    private func cancel(_ id: UUID, waiter: UUID) {
        guard let continuation = entries[id]?.waiters.removeValue(forKey: waiter) else { return }
        continuation.resume(throwing: CancellationError())
        if entries[id]?.waiters.isEmpty == true { remove(id) }
    }
    private func remove(_ id: UUID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.task?.cancel()
        entry.waiters.values.forEach { $0.resume(throwing: CancellationError()) }
    }
    func cancelAll() { for id in Array(entries.keys) { remove(id) } }
}
