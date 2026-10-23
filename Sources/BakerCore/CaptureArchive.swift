import Darwin
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
    public var isVector: Bool { (fileName as NSString).pathExtension == "svg" }

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
    private static let extensions = Set(["png", "jpg", "tiff", "heic", "heif", "bmp", "svg"])
    private var indexURL: URL { directory.appendingPathComponent(Self.indexFileName) }

    private struct Replacement: Codable { let old: CaptureRecord; let new: CaptureRecord }
    private var replacementURL: URL { directory.appendingPathComponent(".baker-replacement.json") }
    public convenience init(directory: URL) throws { try self.init(directory: directory, recovering: true) }
    private init(directory: URL, recovering: Bool) throws {
        guard directory.isFileURL else { throw BakerError(message: "Capture history needs a local folder.", code: .invalidInput) }
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        records = []
        try files.createDirectory(at: self.directory, withIntermediateDirectories: true)
        let descriptor = recovering ? open(self.directory.appendingPathComponent(".baker-history.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR) : -1
        if recovering { guard descriptor >= 0, flock(descriptor, LOCK_EX) == 0 else { if descriptor >= 0 { close(descriptor) }; throw BakerError(message: "Capture history could not be locked.", code: .storageFailed) } }
        defer { if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor) } }
        guard let data = try readIndex() else { return }
        let index: Index
        do { index = try JSONDecoder().decode(Index.self, from: data) }
        catch { throw BakerError(message: "The capture history index is damaged. Existing images have been preserved.", code: .storageFailed) }
        guard index.version == 1 else { throw BakerError(message: "This capture history uses an unsupported index version.", code: .storageFailed) }
        guard index.records.count <= Self.maximumRecords else { throw BakerError(message: "The capture history index exceeds the supported 10,000 records.", code: .resourceLimit) }
        var identifiers = Set<UUID>()
        for record in index.records {
            guard Self.valid(record), identifiers.insert(record.id).inserted else {
                throw BakerError(message: "The capture history index contains an invalid or duplicate record. Existing images have been preserved.", code: .storageFailed)
            }
            let url = self.directory.appendingPathComponent(record.fileName)
            if files.fileExists(atPath: url.path) {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true else {
                    throw BakerError(message: "A capture history image is not a regular local file.", code: .storageFailed)
                }
            }
        }
        records = index.records.sorted(by: Self.newer)
        indexFingerprint = SHA256.hash(data: data)
        if recovering { try recoverReplacement() }
    }
    private func recoverReplacement() throws {
        guard files.fileExists(atPath: replacementURL.path) else { return }
        let values = try replacementURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) < 4096 else {
            throw BakerError(message: "The capture replacement journal is invalid. Existing files were preserved.", code: .storageFailed)
        }
        let change = try JSONDecoder().decode(Replacement.self, from: Data(contentsOf: replacementURL))
        guard Self.valid(change.old), Self.valid(change.new), change.old.id == change.new.id, change.old.fileName != change.new.fileName else {
            throw BakerError(message: "The capture replacement journal is invalid. Existing files were preserved.", code: .storageFailed)
        }
        let obsolete: CaptureRecord
        if records.contains(change.new) { obsolete = change.old }
        else if records.contains(change.old) { obsolete = change.new }
        else { throw BakerError(message: "The interrupted capture replacement needs review. Existing files were preserved.", code: .storageConflict) }
        let url = fileURL(for: obsolete)
        if files.fileExists(atPath: url.path) { try files.removeItem(at: url) }
        try files.removeItem(at: replacementURL)
    }

    /// Copies a supported still image; the caller's source is never moved or removed.
    @discardableResult public func add(source: URL) throws -> CaptureRecord {
        let lockURL = directory.appendingPathComponent(".baker-history.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw BakerError(message: "Capture history could not be locked.", code: .storageFailed) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw BakerError(message: "Capture history is busy.", code: .storageConflict) }
        defer { flock(descriptor, LOCK_UN) }
        let fresh = try CaptureArchive(directory: directory, recovering: false)
        // Additive changes from another instance are safe. Deletions or edits require review.
        let current = Dictionary(uniqueKeysWithValues: fresh.records.map { ($0.id, $0) })
        guard records.allSatisfy({ current[$0.id] == $0 }) else {
            throw BakerError(message: "Capture history was edited outside Baker. Restart Baker to reload it; existing images are preserved.", code: .storageConflict)
        }
        records = fresh.records; indexFingerprint = fresh.indexFingerprint
        guard records.count < Self.maximumRecords else {
            throw BakerError(message: "Capture history has reached 10,000 images. Choose a new history folder; existing images have been kept.", code: .resourceLimit)
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
        guard try Self.inspect(staged) == info else { throw BakerError(message: "The source image changed while it was being archived.", code: .storageConflict) }
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
            catch { throw BakerError(message: "History could not be updated or its new image rolled back. The source and previous history remain intact.", code: .storageFailed) }
            throw error
        }
    }

    /// Replaces the archived capture, retaining its ID/date. A format change replaces the previous file.
    public func replace(source: URL, record: CaptureRecord) throws -> CaptureRecord {
        let descriptor = open(directory.appendingPathComponent(".baker-history.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw BakerError(message: "Capture history could not be locked.", code: .storageFailed) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw BakerError(message: "Capture history is busy.", code: .storageConflict) }
        defer { flock(descriptor, LOCK_UN) }
        let fresh = try CaptureArchive(directory: directory, recovering: false)
        guard fresh.records.contains(record) else { throw BakerError(message: "The capture changed while editing. Reopen it before saving.", code: .storageConflict) }
        let info = try Self.inspect(source)
        guard ["png", "svg"].contains(info.fileExtension) else { throw BakerError(message: "Edited captures must use flattened PNG or self-contained SVG data.", code: .invalidInput) }
        records = fresh.records; indexFingerprint = fresh.indexFingerprint
        let updated = CaptureRecord(id: record.id, createdAt: record.createdAt, fileName: record.id.uuidString.lowercased() + "." + info.fileExtension, pixelWidth: info.width, pixelHeight: info.height)
        let original = fileURL(for: record), destination = fileURL(for: updated)
        let originalData = try Data(contentsOf: original)
        let replacement = try Data(contentsOf: source)
        if destination != original, files.fileExists(atPath: destination.path) { throw BakerError(message: "An edited image already occupies this capture's destination.", code: .storageConflict) }
        guard !files.fileExists(atPath: replacementURL.path) else { throw BakerError(message: "Reopen capture history to finish an interrupted edit.", code: .storageConflict) }
        if destination != original { try JSONEncoder().encode(Replacement(old: record, new: updated)).write(to: replacementURL, options: .atomic) }
        do {
            try replacement.write(to: destination, options: .atomic)
            let changed = records.map { $0.id == record.id ? updated : $0 }
            try persist(changed)
            if original != destination { try files.removeItem(at: original) }
            records = changed
            if destination != original { try? files.removeItem(at: replacementURL) }
            return updated
        } catch {
            try originalData.write(to: original, options: .atomic)
            if destination != original { try? files.removeItem(at: destination) }
            // If persistence succeeded before a file removal failed, restore the old record too.
            if try readIndex().map({ SHA256.hash(data: $0) }) == indexFingerprint { try persist(records) }
            if destination != original { try? files.removeItem(at: replacementURL) }
            throw error
        }
    }

    /// Reconcile Finder deletions and optionally move a reviewed set of images to Trash.
    /// On partial Trash failure, commit only files that are now absent, then report the failure.
    public func reconcile(trashing candidates: [CaptureRemovalCandidate] = [], trash: (URL) throws -> Void = { _ in }) throws -> [CaptureRecord] {
        guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw BakerError(message: "The capture folder is unavailable. History has been preserved.", code: .storageFailed)
        }
        let descriptor = open(directory.appendingPathComponent(".baker-history.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw BakerError(message: "Capture history could not be locked.", code: .storageFailed) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw BakerError(message: "Capture history is busy.", code: .storageConflict) }
        defer { flock(descriptor, LOCK_UN) }
        let fresh = try CaptureArchive(directory: directory, recovering: false)
        records = fresh.records; indexFingerprint = fresh.indexFingerprint
        guard Set(candidates.map { $0.record.id }).count == candidates.count else {
            throw BakerError(message: "The removal review contains duplicate captures.", code: .invalidInput)
        }
        // Validate the complete reviewed set before moving any file.
        for candidate in candidates {
            guard records.contains(candidate.record) else { throw BakerError(message: "Capture history changed. Review the limits again.", code: .storageConflict) }
            let value = try fileURL(for: candidate.record).resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey, .isRegularFileKey])
            guard value.isRegularFile == true, value.isSymbolicLink != true, value.fileSize == candidate.bytes,
                  value.contentModificationDate == candidate.modified else { throw BakerError(message: "A capture changed. Review the limits again.", code: .storageConflict) }
        }
        var trashFailure: Error?
        for candidate in candidates {
            do { try Task.checkCancellation(); try trash(fileURL(for: candidate.record)) }
            catch { trashFailure = error; break }
        }
        let kept = try records.filter { record in
            do { _ = try fileURL(for: record).resourceValues(forKeys: [.isRegularFileKey]); return true }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return false }
        }
        if kept != records { try persist(kept); records = kept }
        if let trashFailure { throw trashFailure }
        return records
    }

    /// Records returned by this archive have validated names; arbitrary names cannot escape the folder.
    public func fileURL(for record: CaptureRecord) -> URL {
        let suffix = (record.fileName as NSString).pathExtension.lowercased()
        let safeSuffix = Self.extensions.contains(suffix) ? suffix : "invalid"
        return directory.appendingPathComponent(record.id.uuidString.lowercased() + "." + safeSuffix)
    }

    public func thumbnail(for record: CaptureRecord, maximumPixelSize: Int = 600) throws -> CGImage {
        guard (1...600).contains(maximumPixelSize), Self.valid(record) else {
            throw BakerError(message: "Capture thumbnails require a valid record and a size from 1 to 600 pixels.", code: .invalidInput)
        }
        return try decodedImage(for: record, maximumPixelSize: maximumPixelSize)
    }

    public func original(for record: CaptureRecord) throws -> CGImage {
        guard Self.valid(record) else { throw BakerError(message: "The saved capture record is invalid.", code: .storageFailed) }
        return try decodedImage(for: record, maximumPixelSize: max(record.pixelWidth, record.pixelHeight))
    }

    /// A display-sized decode; recognition and exports continue to use the saved file.
    public func preview(for record: CaptureRecord) throws -> CGImage {
        guard Self.valid(record) else { throw BakerError(message: "The saved capture record is invalid.", code: .storageFailed) }
        return try decodedImage(for: record, maximumPixelSize: min(2048, max(record.pixelWidth, record.pixelHeight)))
    }

    private func decodedImage(for record: CaptureRecord, maximumPixelSize: Int) throws -> CGImage {
        let url = fileURL(for: record)
        let info = try Self.inspect(url, allowSymbolicLink: false)
        guard info.width == record.pixelWidth, info.height == record.pixelHeight else {
            throw BakerError(message: "The archived image dimensions no longer match its history record.", code: .storageFailed)
        }
        if record.isVector { return try CaptureSVG(data: Data(contentsOf: url)).raster(maximumPixelSize: maximumPixelSize) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
              ] as CFDictionary), max(image.width, image.height) <= maximumPixelSize else {
            throw BakerError(message: "The archived image thumbnail could not be read.", code: .storageFailed)
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
            throw BakerError(message: "The capture history index is not a regular file within the 8 MB limit. Existing images have been preserved.", code: .storageFailed)
        }
        return try Data(contentsOf: indexURL, options: [.mappedIfSafe])
    }

    private func persist(_ updated: [CaptureRecord]) throws {
        let current = try readIndex()
        guard current.map({ SHA256.hash(data: $0) }) == indexFingerprint else {
            throw BakerError(message: "The capture history index changed outside Baker. Reopen history before adding another capture.", code: .storageConflict)
        }
        let data = try JSONEncoder().encode(Index(version: 1, records: updated))
        guard data.count <= Self.maximumIndexBytes else {
            throw BakerError(message: "The capture history index has reached its 8 MB limit. Existing images have been kept.", code: .resourceLimit)
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
        guard url.isFileURL else { throw BakerError(message: "Capture history accepts local images only.", code: .invalidInput) }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, allowSymbolicLink || values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= maximumSourceBytes else {
            throw BakerError(message: "Choose a regular image file no larger than 128 MB.", code: .invalidInput)
        }
        if url.pathExtension.lowercased() == "svg" {
            guard size <= CaptureSVG.maximumBytes else { throw BakerError(message: "The vector image exceeds 8 MB.", code: .resourceLimit) }
            let vector = try CaptureSVG(data: Data(contentsOf: url))
            return ImageInfo(width: vector.width, height: vector.height, fileExtension: "svg")
        }
        guard let image = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(image) == 1,
              let type = CGImageSourceGetType(image) as String?,
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw BakerError(message: "Choose a supported PNG, JPEG, TIFF, HEIC, HEIF or BMP still image.", code: .unsupportedFormat)
        }
        let formats = ["public.png": "png", "public.jpeg": "jpg", "public.tiff": "tiff", "public.heic": "heic", "public.heif": "heif", "com.microsoft.bmp": "bmp"]
        guard let suffix = formats[type] else { throw BakerError(message: "This image format is not supported by capture history.", code: .unsupportedFormat) }
        let w = width.intValue, h = height.intValue
        guard w > 0, h > 0, w <= maximumDimension, h <= maximumDimension, w * h <= maximumPixels else {
            throw BakerError(message: "Capture history images must fit within 8192 pixels per side and 32 megapixels.", code: .resourceLimit)
        }
        return ImageInfo(width: w, height: h, fileExtension: suffix)
    }
}
