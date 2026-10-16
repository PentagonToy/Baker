import CoreGraphics
import Foundation
import PDFKit
import Vision

public enum PDFExportFormat: String, CaseIterable, Sendable {
    case markdown, latex
    public var fileExtension: String { self == .markdown ? "md" : "tex" }
}
public enum PDFTextSource: String, Sendable { case textLayer, vision }

/// Plain text with its original page location. No mathematical or table semantics are inferred.
public struct PDFTextBlock: Sendable {
    public let text: String
    public let bounds: CGRect
    public let source: PDFTextSource
}

public struct PDFPageContent: Sendable {
    public let pageNumber: Int
    public let pageSize: CGSize
    public let blocks: [PDFTextBlock]
    public let source: PDFTextSource
    public let warnings: [String]
}

public struct PDFConversionProgress: Sendable {
    public enum Phase: Sendable { case reading, recognising, writing, completed }
    public let pageNumber: Int
    public let totalPages: Int
    public let phase: Phase
    public let message: String
    public var completedPages: Int { phase == .completed ? pageNumber : max(0, pageNumber - 1) }
}

public struct PDFPageSummary: Sendable {
    public let pageNumber: Int
    public let source: PDFTextSource
    public let blockCount: Int
    public let characterCount: Int
    public let warnings: [String]
}

public struct PDFConversionReport: Sendable {
    public let destination: URL
    public let format: PDFExportFormat
    public let pages: [PDFPageSummary]
    public let bytesWritten: Int
    public let warnings: [String]
    public var totalPages: Int { pages.count }
    public var ocrPages: Int { pages.filter { $0.source == .vision }.count }
}

public struct PDFConversionOptions: Sendable {
    public var maximumPages = 2_000
    public var maximumOutputBytes = 64 * 1_024 * 1_024
    public var maximumPageCharacters = 250_000
    public init() {}
}

/// Synchronous, serial worker intended for Task.detached. Owns at most one page raster at a time.
public enum PDFConverter {
    public static let limitations = [
        "Text and reading order are approximate. Columns, tables, figures and equation structure are not reconstructed.",
        "Mathematical symbols in a PDF text layer remain plain text; LaTeX equations are not inferred.",
        "Scanned pages use Apple Vision text OCR, which may misread mathematical notation or handwriting."
    ]

    public static func convert(source: URL, destination: URL, format: PDFExportFormat,
                               options: PDFConversionOptions = .init(),
                               isCancelled: @Sendable () -> Bool = { false },
                               progress: @Sendable (PDFConversionProgress) -> Void = { _ in }) throws -> PDFConversionReport {
        func checkCancellation() throws { if isCancelled() { throw CancellationError() } }
        try checkCancellation()
        let manager = FileManager.default
        guard source.standardizedFileURL.resolvingSymlinksInPath() != destination.standardizedFileURL.resolvingSymlinksInPath() else {
            throw BakerError(message: "The export must use a different file from the source PDF.")
        }
        guard !manager.fileExists(atPath: destination.path) else { throw BakerError(message: "The export destination already exists.") }
        guard (1...2_000).contains(options.maximumPages), (1...64 * 1_024 * 1_024).contains(options.maximumOutputBytes),
              (1...250_000).contains(options.maximumPageCharacters) else { throw BakerError(message: "PDF resource limits are invalid.") }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let attributes = try manager.attributesOfItem(atPath: source.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value <= 256 * 1_024 * 1_024 else {
            throw BakerError(message: "PDF files are limited to 256 MB.")
        }
        guard let document = PDFDocument(url: source) else { throw BakerError(message: "The PDF is corrupt or could not be opened.") }
        guard !document.isLocked else { throw BakerError(message: "This PDF is password locked. Unlock a copy before converting it.") }
        guard document.allowsCopying else { throw BakerError(message: "This PDF does not allow text extraction. Export an unrestricted copy first.") }
        guard document.pageCount > 0 else { throw BakerError(message: "The PDF has no pages.") }
        guard document.pageCount <= options.maximumPages else { throw BakerError(message: "The PDF exceeds the \(options.maximumPages)-page limit.") }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".baker-pdf-\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: temporary.path, contents: nil) else { throw BakerError(message: "The export file could not be created.") }
        defer { try? manager.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        var written = 0
        func write(_ text: String) throws {
            try checkCancellation()
            let bytes = Data(text.utf8)
            guard bytes.count <= options.maximumOutputBytes - written else { throw BakerError(message: "The export exceeds the output size limit.") }
            try handle.write(contentsOf: bytes)
            written += bytes.count
        }
        if format == .latex {
            try write("% Compile with LuaLaTeX or XeLaTeX. Unicode glyph coverage depends on the chosen font.\n\\documentclass{article}\n\\usepackage{fontspec}\n\\usepackage[margin=25mm]{geometry}\n\\begin{document}\n")
        }
        for warning in limitations { try write(comment(warning, format: format)) }
        var summaries: [PDFPageSummary] = []
        for index in 0..<document.pageCount {
            try checkCancellation()
            let summary: PDFPageSummary = try autoreleasepool {
                guard let page = document.page(at: index) else { throw BakerError(message: "PDF page \(index + 1) could not be read.") }
                progress(.init(pageNumber: index + 1, totalPages: document.pageCount, phase: .reading, message: "Reading page \(index + 1) of \(document.pageCount)"))
                let content = try extract(page: page, pageNumber: index + 1, maximumCharacters: options.maximumPageCharacters,
                    isCancelled: isCancelled, beforeOCR: {
                        progress(.init(pageNumber: index + 1, totalPages: document.pageCount, phase: .recognising, message: "Recognising scanned page \(index + 1)"))
                    })
                try checkCancellation()
                progress(.init(pageNumber: index + 1, totalPages: document.pageCount, phase: .writing, message: "Exporting page \(index + 1)"))
                try write(comment("Page \(content.pageNumber); source: \(content.source.rawValue)", format: format))
                for warning in content.warnings { try write(comment(warning, format: format)) }
                for block in content.blocks {
                    try write((format == .markdown ? escapeMarkdown(block.text) : escapeLaTeX(block.text)) + "\n\n")
                }
                if index + 1 < document.pageCount { try write(format == .markdown ? "---\n\n" : "\\newpage\n") }
                return PDFPageSummary(pageNumber: index + 1, source: content.source, blockCount: content.blocks.count,
                    characterCount: content.blocks.reduce(0) { $0 + $1.text.count }, warnings: content.warnings)
            }
            summaries.append(summary)
            progress(.init(pageNumber: index + 1, totalPages: document.pageCount, phase: .completed, message: "Exported page \(index + 1) of \(document.pageCount)"))
        }
        if format == .latex { try write("\\end{document}\n") }
        try checkCancellation()
        try handle.synchronize()
        try handle.close()
        try checkCancellation()
        // A sibling temporary file keeps final placement on the same volume; existing files are never replaced.
        try manager.moveItem(at: temporary, to: destination)
        let pageWarnings = summaries.flatMap(\.warnings).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return PDFConversionReport(destination: destination, format: format, pages: summaries, bytesWritten: written, warnings: limitations + pageWarnings)
    }

    private static func extract(page: PDFPage, pageNumber: Int, maximumCharacters: Int,
                                isCancelled: () -> Bool, beforeOCR: () -> Void) throws -> PDFPageContent {
        let box = page.bounds(for: .cropBox)
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0,
              box.width <= 1_000_000, box.height <= 1_000_000 else { throw BakerError(message: "PDF page \(pageNumber) has invalid dimensions.") }
        if isCancelled() { throw CancellationError() }
        let native = clean(page.string ?? "")
        guard native.count <= maximumCharacters else { throw BakerError(message: "Page \(pageNumber) exceeds the text size limit.") }
        if !native.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = page.selection(for: box)?.selectionsByLine() ?? []
            var blocks: [PDFTextBlock] = []
            var count = 0
            for line in lines {
                if isCancelled() { throw CancellationError() }
                let text = clean(line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                count += text.count
                guard count <= maximumCharacters else { throw BakerError(message: "Page \(pageNumber) exceeds the text size limit.") }
                blocks.append(.init(text: text, bounds: line.bounds(for: page), source: .textLayer))
            }
            if blocks.isEmpty { blocks = [.init(text: native, bounds: box, source: .textLayer)] }
            return .init(pageNumber: pageNumber, pageSize: box.size, blocks: paragraphs(blocks), source: .textLayer,
                warnings: ["PDF text-layer order and paragraph grouping are approximate; embedded images are not separately recognised."])
        }
        beforeOCR()
        let image = try rasterise(page, box: box)
        if isCancelled() { throw CancellationError() }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        if isCancelled() { throw CancellationError() }
        var count = 0
        let blocks = try (request.results ?? []).compactMap { observation -> PDFTextBlock? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = clean(candidate.string).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            count += text.count
            guard count <= maximumCharacters else { throw BakerError(message: "Page \(pageNumber) exceeds the recognised text size limit.") }
            let b = observation.boundingBox
            return .init(text: text, bounds: CGRect(x: box.minX + b.minX * box.width, y: box.minY + b.minY * box.height, width: b.width * box.width, height: b.height * box.height), source: .vision)
        }
        return .init(pageNumber: pageNumber, pageSize: box.size, blocks: blocks, source: .vision,
            warnings: blocks.isEmpty ? ["No text was found on this page. Figures and blank pages are not reproduced."] : ["Apple Vision OCR used a bounded page raster. Reading order and mathematical notation require review."])
    }

    private static func rasterise(_ page: PDFPage, box: CGRect) throws -> CGImage {
        let scale = min(2, min(4_096 / max(box.width, box.height), sqrt(8_000_000 / (box.width * box.height))))
        let width = max(1, Int(floor(box.width * scale))), height = max(1, Int(floor(box.height * scale)))
        guard width <= 4_096, height <= 4_096, width * height <= 8_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw BakerError(message: "The PDF page could not be rasterised within the memory limit.")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
        context.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .cropBox, to: context)
        guard let image = context.makeImage() else { throw BakerError(message: "The PDF page raster is unavailable.") }
        return image
    }

    private static func paragraphs(_ lines: [PDFTextBlock]) -> [PDFTextBlock] {
        var result: [PDFTextBlock] = []
        for line in lines {
            if let last = result.last {
                let gap = last.bounds.minY - line.bounds.maxY
                let height = max(line.bounds.height, 1)
                if abs(last.bounds.minX - line.bounds.minX) < height, gap >= -height * 0.25, gap < height * 0.65 {
                    result[result.count - 1] = .init(text: last.text + " " + line.text, bounds: last.bounds.union(line.bounds), source: line.source)
                    continue
                }
            }
            result.append(line)
        }
        return result
    }

    private static func clean(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\t" })
    }

    public static func escapeMarkdown(_ text: String) -> String {
        let special = Set("\\`*_{}[]<>#+.!|~-$")
        return clean(text).map { special.contains($0) ? "\\\($0)" : String($0) }.joined()
    }

    public static func escapeLaTeX(_ text: String) -> String {
        let replacements: [Character: String] = ["\\": "\\textbackslash{}", "{": "\\{", "}": "\\}", "$": "\\$", "&": "\\&", "%": "\\%", "#": "\\#", "_": "\\_", "^": "\\textasciicircum{}", "~": "\\textasciitilde{}"]
        return clean(text).map { replacements[$0] ?? String($0) }.joined()
    }

    private static func comment(_ text: String, format: PDFExportFormat) -> String {
        format == .markdown ? "<!-- \(text.replacingOccurrences(of: "--", with: "—")) -->\n\n" : "% \(text.replacingOccurrences(of: "\n", with: " "))\n"
    }
}
