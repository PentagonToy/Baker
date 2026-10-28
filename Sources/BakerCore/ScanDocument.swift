import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import CoreText
import Vision

public struct ScanPage: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let fileName: String
    public let width: Int
    public let height: Int
    public let fingerprint: String
}

/// A recoverable draft owns page files; capture and PDF export never retain the whole book.
public actor ScanDocument {
    public static let pageLimit = 500
    private struct Manifest: Codable { var version = 1; var pages: [ScanPage] = [] }
    public nonisolated let directory: URL
    private var manifest: Manifest
    private var discarded = false
    private var pageBytes: [UUID: Int64] = [:]
    private var usedBytes: Int64 = 0

    public init(directory: URL, resume: Bool = false) throws {
        self.directory = directory
        if resume {
            let manifestURL = directory.appendingPathComponent("scan.json")
            let metadata = try manifestURL.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey])
            guard metadata.isRegularFile == true, metadata.isSymbolicLink != true else { throw BakerError(message: "This scan draft is unavailable.", code: .fileAccessDenied) }
            let size = metadata.fileSize ?? Int.max
            guard size <= 1_048_576 else { throw BakerError(message: "This scan draft is too large.", code: .invalidInput) }
            let data = try Data(contentsOf: directory.appendingPathComponent("scan.json"))
            guard data.count <= 1_048_576 else { throw BakerError(message: "This scan draft is too large.", code: .invalidInput) }
            manifest = try JSONDecoder().decode(Manifest.self, from: data)
            guard manifest.version == 1, manifest.pages.count <= Self.pageLimit,
                  Set(manifest.pages.map(\.id)).count == manifest.pages.count,
                  manifest.pages.allSatisfy({ Self.valid($0) }) else {
                throw BakerError(message: "This scan draft is invalid.", code: .invalidInput)
            }
        } else {
            if FileManager.default.fileExists(atPath: directory.path) {
                let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true,
                      try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty else {
                    throw BakerError(message: "A scan draft already exists here.", code: .storageConflict)
                }
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            manifest = Manifest()
            try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("scan.json"), options: .atomic)
        }
        // Read disk sizes once when opening a draft, not for every new capture.
        for page in manifest.pages {
            let size = (try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(page.fileName).path)[.size] as? NSNumber)?.int64Value ?? 0
            pageBytes[page.id] = max(0, size); usedBytes += max(0, size)
        }
    }
    public func pages() -> [ScanPage] { manifest.pages }
    public func storageBytes() -> Int64 { usedBytes }
    private static func valid(_ page: ScanPage) -> Bool {
        page.fileName == page.id.uuidString.lowercased() + ".png" && (2...8192).contains(page.width) && (2...8192).contains(page.height)
            && page.width <= 32_000_000 / page.height && page.fingerprint.count == 64
    }
    private func file(_ page: ScanPage) throws -> URL {
        guard !discarded, Self.valid(page), manifest.pages.contains(page) else { throw BakerError(message: "This scan page is unavailable.", code: .invalidState) }
        let url = directory.appendingPathComponent(page.fileName)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw BakerError(message: "The scan page file is unavailable.", code: .fileAccessDenied) }
        return url
    }
    public func preview(_ page: ScanPage, maximum: Int = 1200) throws -> CGImage {
        try Task.checkCancellation()
        guard (32...1600).contains(maximum), let source = CGImageSourceCreateWithURL(try file(page) as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maximum, kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw BakerError(message: "Could not open this scan page.", code: .previewFailed)
        }
        try Task.checkCancellation(); return image
    }
    /// Exact downsample fingerprint is a duplicate hint, never a reason to discard a manual capture.
    public static func fingerprint(_ image: CGImage) throws -> String {
        var bytes = [UInt8](repeating: 0, count: 96 * 96 * 4)
        let ok = bytes.withUnsafeMutableBytes { data -> Bool in
            guard let c = CGContext(data: data.baseAddress, width: 96, height: 96, bitsPerComponent: 8, bytesPerRow: 384,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            c.interpolationQuality = .low; c.draw(image, in: CGRect(x: 0, y: 0, width: 96, height: 96)); return true
        }
        guard ok else { throw BakerError(message: "Could not compare scan pages.", code: .captureFailed) }
        return SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    }
    /// A new page and manifest are committed before old retake files are removed.
    public func append(_ image: CGImage, replacing id: UUID? = nil, rejectDuplicate: Bool = false) throws -> ScanPage? {
        try Task.checkCancellation()
        guard !discarded, image.width >= 2, image.height >= 2, image.width <= 8192, image.height <= 8192,
              image.width <= 32_000_000 / image.height else { throw BakerError(message: "Choose a smaller scan area.", code: .invalidInput) }
        let index = id.flatMap { id in manifest.pages.firstIndex { $0.id == id } }
        guard id == nil || index != nil else { throw BakerError(message: "Select a page to retake.", code: .invalidInput) }
        guard index != nil || manifest.pages.count < Self.pageLimit else { throw BakerError(message: "This scan has reached 500 pages. Save it before starting another.", code: .resourceLimit) }
        let files = FileManager.default
        let required = Int64(image.width * image.height * 4) + 64_000_000
        let capacity = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        if let capacity, capacity < required { throw BakerError(message: "Not enough space for another scan page. Save the current scan first.", code: .insufficientSpace) }
        guard usedBytes + Int64(image.width * image.height * 4) <= 2_000_000_000 else { throw BakerError(message: "This draft has reached its size limit. Save it before adding more pages.", code: .resourceLimit) }
        let hash = try Self.fingerprint(image)
        if rejectDuplicate, manifest.pages.last?.fingerprint == hash { return nil }
        let pageID = UUID()
        let page = ScanPage(id: pageID, fileName: pageID.uuidString.lowercased() + ".png", width: image.width, height: image.height, fingerprint: hash)
        let target = directory.appendingPathComponent(page.fileName)
        guard let output = CGImageDestinationCreateWithURL(target as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw BakerError(message: "Could not write the scan page.", code: .storageFailed)
        }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { try? FileManager.default.removeItem(at: target); throw BakerError(message: "Could not save the scan page.", code: .storageFailed) }
        var next = manifest
        let previous = index.map { next.pages[$0] }
        if let index { next.pages[index] = page } else { next.pages.append(page) }
        let size: Int64
        do {
            size = try (files.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
            try Task.checkCancellation(); try persist(next)
        } catch { try? files.removeItem(at: target); throw error }
        if let previous { usedBytes -= pageBytes.removeValue(forKey: previous.id) ?? 0 }
        pageBytes[page.id] = max(0, size); usedBytes += max(0, size)
        if let previous { try? FileManager.default.removeItem(at: directory.appendingPathComponent(previous.fileName)) }
        return page
    }
    public func remove(_ id: UUID) throws {
        guard let page = manifest.pages.first(where: { $0.id == id }) else { return }
        var next = manifest; next.pages.removeAll { $0.id == id }; try persist(next)
        usedBytes -= pageBytes.removeValue(forKey: id) ?? 0
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(page.fileName))
    }
    public func move(_ id: UUID, by offset: Int) throws {
        guard let i = manifest.pages.firstIndex(where: { $0.id == id }), manifest.pages.indices.contains(i + offset) else { return }
        var next = manifest; next.pages.swapAt(i, i + offset); try persist(next)
    }
    private func persist(_ next: Manifest) throws {
        guard !discarded else { throw BakerError(message: "This scan has ended.", code: .invalidState) }
        try JSONEncoder().encode(next).write(to: directory.appendingPathComponent("scan.json"), options: .atomic)
        manifest = next
    }
    public func discard() throws {
        guard !discarded else { return }
        try FileManager.default.removeItem(at: directory); discarded = true; manifest.pages = []; pageBytes = [:]; usedBytes = 0
    }
    /// One raster and OCR request at a time; publish only a complete, uncancelled PDF.
    public func export(to destination: URL, searchable: Bool, languages: [String], replace: Bool = false,
                       progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws {
        guard !discarded, !manifest.pages.isEmpty, destination.isFileURL, destination.pathExtension.lowercased() == "pdf" else {
            throw BakerError(message: "Add a page and choose a PDF destination.", code: .invalidInput)
        }
        let files = FileManager.default
        guard !destination.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/") else {
            throw BakerError(message: "Save the PDF outside its working draft.", code: .invalidInput)
        }
        if files.fileExists(atPath: destination.path), !replace { throw BakerError(message: "A file already exists at this destination.", code: .storageConflict) }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".baker-scan-" + UUID().uuidString + ".pdf")
        defer { try? files.removeItem(at: staging) }
        guard let pdf = CGContext(staging as CFURL, mediaBox: nil, [kCGPDFContextCreator: "Baker"] as CFDictionary) else {
            throw BakerError(message: "Could not create the PDF. Choose a writable folder.", code: .exportFailed)
        }
        var pdfClosed = false
        do {
            for (index, page) in manifest.pages.enumerated() {
                try Task.checkCancellation()
                let request = searchable ? VNRecognizeTextRequest() : nil
                try await withTaskCancellationHandler {
                    try autoreleasepool {
                        guard let source = CGImageSourceCreateWithURL(try file(page) as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                              (properties[kCGImagePropertyPixelWidth] as? Int) == page.width,
                              (properties[kCGImagePropertyPixelHeight] as? Int) == page.height,
                              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw BakerError(message: "A scan page could not be read. Retake it before saving.", code: .exportFailed) }
                        var box = CGRect(x: 0, y: 0, width: CGFloat(page.width) / 2, height: CGFloat(page.height) / 2)
                        pdf.beginPage(mediaBox: &box); pdf.draw(image, in: box)
                        if let request {
                            try OCRLanguages.configure(request, languages: languages); try Task.checkCancellation()
                            try VNImageRequestHandler(cgImage: image).perform([request]); try Task.checkCancellation()
                            Self.drawText(request.results ?? [], in: pdf, box: box)
                        }
                        pdf.endPage()
                    }
                } onCancel: {
                    request?.cancel()
                }
                progress(index + 1, manifest.pages.count)
            }
            pdf.closePDF(); pdfClosed = true; try Task.checkCancellation()
            if files.fileExists(atPath: destination.path) {
                guard replace else { throw BakerError(message: "A file appeared at the destination. Choose another name.", code: .storageConflict) }
                _ = try files.replaceItemAt(destination, withItemAt: staging)
            } else { try files.moveItem(at: staging, to: destination) }
        } catch { if !pdfClosed { pdf.closePDF() }; try Task.checkCancellation(); throw error }
    }
    private static func drawText(_ observations: [VNRecognizedTextObservation], in context: CGContext, box: CGRect) {
        context.saveGState(); defer { context.restoreGState() }; context.setTextDrawingMode(.invisible)
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first, !candidate.string.isEmpty else { continue }
            let r = observation.boundingBox
            let rect = CGRect(x: r.minX * box.width, y: r.minY * box.height, width: r.width * box.width, height: r.height * box.height)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: candidate.string,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, max(1, rect.height), nil)]))
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            guard width > 0 else { continue }
            context.saveGState(); context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: rect.width / width, y: 1); context.textPosition = .zero; CTLineDraw(line, context); context.restoreGState()
        }
    }
}
