import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

public struct CaptureRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let fileName: String
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(id: UUID, createdAt: Date, fileName: String, pixelWidth: Int, pixelHeight: Int) {
        self.id = id; self.createdAt = createdAt; self.fileName = fileName
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
    }
}

/// A synchronous archive owned by one serial caller, normally the main actor.
/// Only metadata is retained; image files and thumbnails are read on demand.
public final class CaptureArchive {
    public static let maximumRecords = 10_000
    public static let maximumPixels = 32_000_000
    public static let maximumDimension = 8192
    public static let maximumIndexBytes = 8 * 1024 * 1024
    public static let maximumSourceBytes = 128 * 1024 * 1024
    public static let indexFileName = ".baker-history.json"
    public let directory: URL
    public private(set) var records: [CaptureRecord]
    private var indexFingerprint: SHA256.Digest?
    private let files = FileManager.default

    private struct Index: Codable {
        let version: Int
        let records: [CaptureRecord]
    }
    private struct ImageInfo: Equatable {
        let width: Int
        let height: Int
        let fileExtension: String
    }
    private static let extensions = Set(["png", "jpg", "tiff", "heic", "heif", "bmp"])
    private var indexURL: URL { directory.appendingPathComponent(Self.indexFileName) }

    public init(directory: URL) throws {
        guard directory.isFileURL else { throw BakerError(message: "Capture history needs a local folder.") }
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        records = []
        try files.createDirectory(at: self.directory, withIntermediateDirectories: true)
        guard let data = try readIndex() else { return }
        let index: Index
        do { index = try JSONDecoder().decode(Index.self, from: data) }
        catch { throw BakerError(message: "The capture history index is damaged. Existing images have been preserved.") }
        guard index.version == 1 else { throw BakerError(message: "This capture history uses an unsupported index version.") }
        guard index.records.count <= Self.maximumRecords else { throw BakerError(message: "The capture history index exceeds the supported 10,000 records.") }
        var identifiers = Set<UUID>()
        for record in index.records {
            guard Self.valid(record), identifiers.insert(record.id).inserted else {
                throw BakerError(message: "The capture history index contains an invalid or duplicate record. Existing images have been preserved.")
            }
            let url = self.directory.appendingPathComponent(record.fileName)
            if files.fileExists(atPath: url.path) {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    throw BakerError(message: "A capture history image is not a regular local file.")
                }
            }
        }
        records = index.records.sorted(by: Self.newer)
        indexFingerprint = SHA256.hash(data: data)
    }

    /// Copies a supported still image; the caller's source is never moved or removed.
    @discardableResult public func add(source: URL) throws -> CaptureRecord {
        guard records.count < Self.maximumRecords else {
            throw BakerError(message: "Capture history has reached 10,000 images. Choose a new history folder; existing images have been kept.")
        }
        let sourceURL = source.standardizedFileURL.resolvingSymlinksInPath()
        let info = try Self.inspect(sourceURL)
        let identifier = UUID()
        let record = CaptureRecord(id: identifier, createdAt: Date(), fileName: identifier.uuidString.lowercased() + "." + info.fileExtension, pixelWidth: info.width, pixelHeight: info.height)
        let destination = fileURL(for: record)
        let staging = directory.appendingPathComponent(".baker-import-" + UUID().uuidString.lowercased(), isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }
        let staged = staging.appendingPathComponent(record.fileName)
        try files.copyItem(at: sourceURL, to: staged)
        guard try Self.inspect(staged) == info else { throw BakerError(message: "The source image changed while it was being archived.") }
        // moveItem refuses to overwrite an existing destination.
        try files.moveItem(at: staged, to: destination)
        do {
            let updated = ([record] + records).sorted(by: Self.newer)
            try persist(updated)
            records = updated
            return record
        } catch {
            // Only this operation's freshly generated file is rolled back.
            do { try files.removeItem(at: destination) }
            catch { throw BakerError(message: "History could not be updated or its new image rolled back. The source and previous history remain intact.") }
            throw error
        }
    }

    /// Records returned by this archive have validated names; arbitrary names cannot escape the folder.
    public func fileURL(for record: CaptureRecord) -> URL {
        let suffix = (record.fileName as NSString).pathExtension.lowercased()
        let safeSuffix = Self.extensions.contains(suffix) ? suffix : "invalid"
        return directory.appendingPathComponent(record.id.uuidString.lowercased() + "." + safeSuffix)
    }

    public func thumbnail(for record: CaptureRecord, maximumPixelSize: Int = 600) throws -> CGImage {
        guard (1...600).contains(maximumPixelSize), Self.valid(record) else {
            throw BakerError(message: "Capture thumbnails require a valid record and a size from 1 to 600 pixels.")
        }
        let url = fileURL(for: record)
        let info = try Self.inspect(url, allowSymbolicLink: false)
        guard info.width == record.pixelWidth, info.height == record.pixelHeight else {
            throw BakerError(message: "The archived image dimensions no longer match its history record.")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
              ] as CFDictionary), max(image.width, image.height) <= maximumPixelSize else {
            throw BakerError(message: "The archived image thumbnail could not be read.")
        }
        return image
    }

    private func readIndex() throws -> Data? {
        // resourceValues also detects a dangling symlink, which fileExists would miss.
        let values: URLResourceValues
        do { values = try indexURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
        guard values.isSymbolicLink != true, values.isRegularFile == true,
              let size = values.fileSize, size <= Self.maximumIndexBytes else {
            throw BakerError(message: "The capture history index is not a regular file within the 8 MB limit. Existing images have been preserved.")
        }
        return try Data(contentsOf: indexURL, options: [.mappedIfSafe])
    }

    private func persist(_ updated: [CaptureRecord]) throws {
        let current = try readIndex()
        guard current.map({ SHA256.hash(data: $0) }) == indexFingerprint else {
            throw BakerError(message: "The capture history index changed outside Baker. Reopen history before adding another capture.")
        }
        let data = try JSONEncoder().encode(Index(version: 1, records: updated))
        guard data.count <= Self.maximumIndexBytes else {
            throw BakerError(message: "The capture history index has reached its 8 MB limit. Existing images have been kept.")
        }
        try data.write(to: indexURL, options: .atomic)
        indexFingerprint = SHA256.hash(data: data)
    }

    private static func newer(_ lhs: CaptureRecord, _ rhs: CaptureRecord) -> Bool {
        lhs.createdAt == rhs.createdAt ? lhs.id.uuidString > rhs.id.uuidString : lhs.createdAt > rhs.createdAt
    }

    private static func valid(_ record: CaptureRecord) -> Bool {
        let suffix = (record.fileName as NSString).pathExtension
        return record.createdAt.timeIntervalSinceReferenceDate.isFinite &&
            record.pixelWidth > 0 && record.pixelHeight > 0 &&
            record.pixelWidth <= maximumDimension && record.pixelHeight <= maximumDimension &&
            record.pixelWidth * record.pixelHeight <= maximumPixels && extensions.contains(suffix) &&
            record.fileName == record.id.uuidString.lowercased() + "." + suffix
    }

    private static func inspect(_ url: URL, allowSymbolicLink: Bool = true) throws -> ImageInfo {
        guard url.isFileURL else { throw BakerError(message: "Capture history accepts local images only.") }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, allowSymbolicLink || values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximumSourceBytes else {
            throw BakerError(message: "Choose a regular image file no larger than 128 MB.")
        }
        guard let image = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(image) == 1,
              let type = CGImageSourceGetType(image) as String?,
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw BakerError(message: "Choose a supported PNG, JPEG, TIFF, HEIC, HEIF or BMP still image.")
        }
        let formats = ["public.png": "png", "public.jpeg": "jpg", "public.tiff": "tiff", "public.heic": "heic", "public.heif": "heif", "com.microsoft.bmp": "bmp"]
        guard let suffix = formats[type] else { throw BakerError(message: "This image format is not supported by capture history.") }
        let w = width.intValue, h = height.intValue
        guard w > 0, h > 0, w <= maximumDimension, h <= maximumDimension, w * h <= maximumPixels else {
            throw BakerError(message: "Capture history images must fit within 8192 pixels per side and 32 megapixels.")
        }
        return ImageInfo(width: w, height: h, fileExtension: suffix)
    }
}
