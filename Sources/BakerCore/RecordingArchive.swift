import AVFoundation
import Foundation
import ImageIO

public struct RecordingRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let fileName: String
    public var isGIF: Bool { fileName.hasSuffix(".gif") }
}

/// Stores metadata separately from still-image history. Movies are copied on disk, never loaded as Data.
public final class RecordingArchive {
    public let directory: URL
    private let files = FileManager.default
    private var indexURL: URL { directory.appendingPathComponent(".baker-recordings.json") }
    private struct Index: Codable { let version: Int; var records: [RecordingRecord] }
    public init(directory: URL) { self.directory = directory }
    public func records() throws -> [RecordingRecord] {
        guard files.fileExists(atPath: indexURL.path) else { return [] }
        let size = try indexURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard size.isRegularFile == true, size.isSymbolicLink != true, (size.fileSize ?? Int.max) <= 8 * 1024 * 1024 else {
            throw BakerError(message: "The recording history index is invalid. Recording files have been preserved.", code: .storageFailed)
        }
        let index = try JSONDecoder().decode(Index.self, from: Data(contentsOf: indexURL))
        guard index.version == 1, index.records.count <= 10_000, Set(index.records.map(\.id)).count == index.records.count,
              index.records.allSatisfy({ $0.fileName == "Baker-\($0.id.uuidString).mp4" || $0.fileName == "Baker-\($0.id.uuidString).gif" }) else {
            throw BakerError(message: "The recording history index is unsupported or damaged. Recording files have been preserved.", code: .storageFailed)
        }
        return try index.records.filter { record in
            let url = directory.appendingPathComponent(record.fileName)
            guard files.fileExists(atPath: url.path) else { return false }
            return try regularFile(url)
        }.sorted { $0.createdAt > $1.createdAt }
    }
    public func add(_ source: URL) throws -> RecordingRecord {
        try Task.checkCancellation()
        guard source.isFileURL, ["mp4", "gif"].contains(source.pathExtension.lowercased()), try regularFile(source) else {
            throw BakerError(message: "Choose a local MP4 or GIF recording.", code: .invalidInput)
        }
        var values = try records()
        guard values.count < 10_000 else { throw BakerError(message: "Recording history is full. Move older recordings to another folder.", code: .resourceLimit) }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID(), ext = source.pathExtension.lowercased()
        let record = RecordingRecord(id: id, createdAt: Date(), fileName: "Baker-\(id.uuidString).\(ext)")
        let destination = directory.appendingPathComponent(record.fileName)
        // A failed index update preserves the source and removes only this new copy.
        do {
            try files.copyItem(at: source, to: destination)
            values.insert(record, at: 0)
            try JSONEncoder().encode(Index(version: 1, records: values)).write(to: indexURL, options: .atomic)
        } catch { try? files.removeItem(at: destination); throw error }
        return record
    }
    public func thumbnail(_ record: RecordingRecord) throws -> CGImage {
        let url = directory.appendingPathComponent(record.fileName)
        guard (record.fileName == "Baker-\(record.id.uuidString).mp4" || record.fileName == "Baker-\(record.id.uuidString).gif"), try regularFile(url) else { throw BakerError(message: "The recording is missing.", code: .invalidInput) }
        if record.isGIF {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 640, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                throw BakerError(message: "The GIF preview could not be opened.", code: .previewFailed)
            }
            return image
        }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: 640, height: 640)
        return try generator.copyCGImage(at: .zero, actualTime: nil)
    }
    private func regularFile(_ url: URL) throws -> Bool {
        let value = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return value.isRegularFile == true && value.isSymbolicLink != true
    }
}
