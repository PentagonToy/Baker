import AppKit
import BakerCore
import ImageIO

struct StoredCapture: @unchecked Sendable {
    let record: CaptureRecord
    let thumbnail: CGImage
}

/// Serial disk and image work stays off the interface thread.
actor CaptureStore {
    nonisolated let directory: URL
    private var archive: CaptureArchive?
    init(directory: URL) { self.directory = directory }
    private func opened() throws -> CaptureArchive {
        if let archive { return archive }
        let value = try CaptureArchive(directory: directory)
        archive = value
        return value
    }
    func records() throws -> [CaptureRecord] { try opened().records }
    func add(file: URL) throws -> StoredCapture {
        try Task.checkCancellation()
        let archive = try opened()
        let record = try archive.add(source: file)
        return StoredCapture(record: record, thumbnail: try archive.thumbnail(for: record))
    }
    func add(image: CGImage) throws -> StoredCapture {
        try Task.checkCancellation()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("baker-capture-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, "public.png" as CFString, 1, nil) else {
            throw BakerError(message: "Could not prepare the captured image.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw BakerError(message: "Could not encode the captured image.") }
        do {
            let result = try add(file: temporary)
            try? FileManager.default.removeItem(at: temporary)
            return result
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: temporary)
            throw CancellationError()
        } catch {
            throw BakerError(message: "\(error.localizedDescription) Original retained at \(temporary.path)")
        }
    }
    func thumbnail(_ record: CaptureRecord) throws -> CGImage { try opened().thumbnail(for: record) }
}
