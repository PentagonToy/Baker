import AppKit
import CoreGraphics
import Foundation
import PDFKit
import Vision

public enum PDFExportFormat: String, CaseIterable, Sendable {
    case markdown, latex
    public var fileExtension: String { self == .markdown ? "md" : "tex" }
}
public enum PDFTextSource: String, Sendable { case textLayer, vision, tesseract, structured }

/// Plain text with its original page location. No mathematical or table semantics are inferred.
public struct PDFTextBlock: Sendable {
    public let text: String
    public let bounds: CGRect
    public let source: PDFTextSource
    public let headingLevel: Int?
    public init(text: String, bounds: CGRect, source: PDFTextSource, headingLevel: Int? = nil) {
        self.text = text; self.bounds = bounds; self.source = source; self.headingLevel = headingLevel
    }
}

public struct PDFPageContent: Sendable {
    public let pageNumber: Int
    public let pageSize: CGSize
    public let blocks: [PDFTextBlock]
    public let source: PDFTextSource
    public let warnings: [String]
}

public struct PDFConversionProgress: Sendable {
    public init(pageNumber: Int, totalPages: Int, phase: Phase, message: String, provider: String? = nil) {
        self.pageNumber = pageNumber; self.totalPages = totalPages; self.phase = phase; self.message = message; self.provider = provider
    }
    public enum Phase: Sendable { case preparing, reading, recognising, writing, completed, finalising }
    public let pageNumber: Int
    public let totalPages: Int
    public let phase: Phase
    public let message: String
    public let provider: String?
    public var completedPages: Int { phase == .completed || phase == .finalising ? min(totalPages, pageNumber) : max(0, pageNumber - 1) }
}

public struct PDFPageSummary: Sendable {
    public init(pageNumber: Int, source: PDFTextSource, blockCount: Int, characterCount: Int, warnings: [String]) {
        self.pageNumber = pageNumber; self.source = source; self.blockCount = blockCount; self.characterCount = characterCount; self.warnings = warnings
    }
    public let pageNumber: Int
    public let source: PDFTextSource
    public let blockCount: Int
    public let characterCount: Int
    public let warnings: [String]
}

public struct PDFConversionReport: Sendable {
    public init(destination: URL, format: PDFExportFormat, pages: [PDFPageSummary], bytesWritten: Int, warnings: [String], provider: String? = nil) {
        self.destination = destination; self.format = format; self.pages = pages; self.bytesWritten = bytesWritten; self.warnings = warnings; self.provider = provider
    }
    public var provider: String?
    public let destination: URL
    public let format: PDFExportFormat
    public let pages: [PDFPageSummary]
    public let bytesWritten: Int
    public let warnings: [String]
    public var totalPages: Int { pages.count }
    public var ocrPages: Int { pages.filter { $0.source != .textLayer }.count }
}

public struct PDFConversionOptions: Sendable {
    public var documentEngine: PDFDocumentEngine?
    public var finnishTextMode = false
    public var tesseractExecutable = ""
    public var recognitionLanguages: [String] = []
    public var maximumPages = 2_000
    public var maximumOutputBytes = 64 * 1_024 * 1_024
    public var maximumPageCharacters = 250_000
    public init() {}
}

/// Synchronous, serial worker intended for Task.detached. Owns at most one page raster at a time.
public enum PDFConverter {
    public static let limitations = [
        "Reading order and headings are inferred from page geometry and typography. Complex layouts require review; tables, figures and equation structure are not yet recognised by this extractor.",
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
            throw BakerError(message: "The export must use a different file from the source PDF.", code: .exportFailed)
        }
        guard !manager.fileExists(atPath: destination.path) else { throw BakerError(message: "The export destination already exists.", code: .exportFailed) }
        guard (1...2_000).contains(options.maximumPages), (1...64 * 1_024 * 1_024).contains(options.maximumOutputBytes),
              (1...250_000).contains(options.maximumPageCharacters) else { throw BakerError(message: "PDF resource limits are invalid.", code: .configurationInvalid) }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let attributes = try manager.attributesOfItem(atPath: source.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value <= 256 * 1_024 * 1_024 else {
            throw BakerError(message: "PDF files are limited to 256 MB.", code: .resourceLimit)
        }
        guard let document = PDFDocument(url: source) else { throw BakerError(message: "The PDF is corrupt or could not be opened.", code: .invalidInput) }
        guard !document.isLocked else { throw BakerError(message: "This PDF is password locked. Unlock a copy before converting it.", code: .invalidInput) }
        guard document.allowsCopying else { throw BakerError(message: "This PDF does not allow text extraction. Export an unrestricted copy first.", code: .invalidInput) }
        guard document.pageCount > 0 else { throw BakerError(message: "The PDF has no pages.", code: .invalidInput) }
        guard document.pageCount <= options.maximumPages else { throw BakerError(message: "The PDF exceeds the \(options.maximumPages)-page limit.", code: .resourceLimit) }
        if let engine = options.documentEngine {
            return try PDFDocumentWorker.convert(source: source, destination: destination, format: format, engine: engine,
                                                 options: options, expectedPages: document.pageCount, isCancelled: isCancelled, progress: progress)
        }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".baker-pdf-\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: temporary.path, contents: nil) else { throw BakerError(message: "The export file could not be created.", code: .exportFailed) }
        defer { try? manager.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        var written = 0
        func write(_ text: String) throws {
            try checkCancellation()
            let bytes = Data(text.utf8)
            guard bytes.count <= options.maximumOutputBytes - written else { throw BakerError(message: "The export exceeds the output size limit.", code: .resourceLimit) }
            try handle.write(contentsOf: bytes)
            written += bytes.count
        }
        if format == .latex {
            try write("% Compile with LuaLaTeX or XeLaTeX. Unicode glyph coverage depends on the chosen font.\n\\documentclass{article}\n\\usepackage{fontspec}\n\\usepackage{amsmath,graphicx,longtable}\n\\usepackage[margin=25mm]{geometry}\n\\begin{document}\n")
        }
        for warning in limitations { try write(comment(warning, format: format)) }
        var summaries: [PDFPageSummary] = []
        for index in 0..<document.pageCount {
            try checkCancellation()
            let summary: PDFPageSummary = try autoreleasepool {
                guard let page = document.page(at: index) else { throw BakerError(message: "PDF page \(index + 1) could not be read.", code: .recognitionFailed) }
                progress(.init(pageNumber: index + 1, totalPages: document.pageCount, phase: .reading, message: "Reading page \(index + 1) of \(document.pageCount)"))
                let content = try extract(page: page, pageNumber: index + 1, maximumCharacters: options.maximumPageCharacters, languages: options.recognitionLanguages, finnish: options.finnishTextMode, tesseractPath: options.tesseractExecutable,
                    isCancelled: isCancelled, beforeOCR: {
                        progress(.init(pageNumber: index + 1, totalPages: document.pageCount, phase: .recognising, message: "Recognising scanned page \(index + 1)"))
                    })
                try checkCancellation()
                progress(.init(pageNumber: index + 1, totalPages: document.pageCount, phase: .writing, message: "Exporting page \(index + 1)"))
                try write(comment("Page \(content.pageNumber); source: \(content.source.rawValue)", format: format))
                for warning in content.warnings { try write(comment(warning, format: format)) }
                let regions = content.blocks.enumerated().map { index, block in
                    PDFRegion(id: index, bounds: block.bounds, content: block.headingLevel.map { .heading(block.text, level: $0) } ?? .text(block.text))
                }
                try write(PDFStructure.render(regions, format: format))
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

    private static func extract(page: PDFPage, pageNumber: Int, maximumCharacters: Int, languages: [String], finnish: Bool, tesseractPath: String,
                                isCancelled: () -> Bool, beforeOCR: () -> Void) throws -> PDFPageContent {
        let box = page.bounds(for: .cropBox)
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0,
              box.width <= 1_000_000, box.height <= 1_000_000 else { throw BakerError(message: "PDF page \(pageNumber) has invalid dimensions.", code: .invalidInput) }
        if isCancelled() { throw CancellationError() }
        let native = clean(page.string ?? "")
        guard native.count <= maximumCharacters else { throw BakerError(message: "Page \(pageNumber) exceeds the text size limit.", code: .resourceLimit) }
        if !native.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard page.numberOfCharacters <= maximumCharacters else { throw BakerError(message: "Page exceeds the character geometry limit.", code: .resourceLimit) }
            let characterBoxes = (0..<page.numberOfCharacters).map { page.characterBounds(at: $0) }.filter { !$0.isEmpty && $0.midY.isFinite && $0.minX.isFinite }.sorted { $0.midY < $1.midY }
            let lines = (page.selection(for: box)?.selectionsByLine() ?? []).flatMap { splitColumns($0, page: page, characterBoxes: characterBoxes) }
            var blocks: [PDFTextBlock] = []
            var fontWeights: [Int: Int] = [:]
            for (selection, _) in lines {
                guard let attributed = selection.attributedString, attributed.length > 0,
                      let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else { continue }
                fontWeights[Int((font.pointSize * 10).rounded()), default: 0] += (selection.string ?? "").filter { $0.isLetter }.count
            }
            let bodySize = CGFloat(fontWeights.max { $0.value < $1.value }?.key ?? 0) / 10
            var count = 0
            for (line, lineBounds) in lines {
                if isCancelled() { throw CancellationError() }
                let text = clean(line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                count += text.count
                guard count <= maximumCharacters else { throw BakerError(message: "Page \(pageNumber) exceeds the text size limit.", code: .resourceLimit) }
                var heading: Int?
                if let attributed = line.attributedString, attributed.length > 0,
                   let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont,
                   bodySize > 0, text.count < 180 {
                    let numbered = text.range(of: #"^\d+(?:\.\d+)*\.?\s+\p{L}"#, options: .regularExpression) != nil
                    let bold = font.fontDescriptor.symbolicTraits.contains(.bold)
                    if (font.pointSize >= bodySize * 1.35 && lineBounds.minY >= box.minY + box.height * 0.8) || (bold && numbered) {
                        let prefix = text.split(separator: " ").first ?? ""
                        heading = numbered ? min(3, prefix.filter { $0 == "." }.count + (prefix.hasSuffix(".") ? 0 : 1)) : 1
                    }
                }
                blocks.append(.init(text: text, bounds: lineBounds, source: .textLayer, headingLevel: heading))
            }
            if blocks.isEmpty { blocks = [.init(text: native, bounds: box, source: .textLayer)] }
            return .init(pageNumber: pageNumber, pageSize: box.size, blocks: paragraphs(orderedLines(blocks)), source: .textLayer,
                warnings: ["PDF text-layer order and paragraph grouping are approximate; embedded images are not separately recognised."])
        }
        beforeOCR()
        let image = try rasterise(page, box: box)
        if isCancelled() { throw CancellationError() }
        if finnish || OCRLanguages.usesTesseract(languages) {
            let text = clean(try FinnishOCR.recognise(image, executable: tesseractPath, languages: finnish && !languages.contains("fi-FI") ? ["fi-FI"] : languages))
            if isCancelled() { throw CancellationError() }
            guard text.count <= maximumCharacters else { throw BakerError(message: "Page \(pageNumber) exceeds the recognised text size limit.", code: .resourceLimit) }
            return .init(pageNumber: pageNumber, pageSize: box.size, blocks: text.isEmpty ? [] : [.init(text: text, bounds: box, source: .tesseract)], source: .tesseract,
                warnings: [text.isEmpty ? "No text was found on this page." : "Tesseract OCR used a bounded page raster. Paragraphs, columns and maths require review."])
        }
        let request = VNRecognizeTextRequest()
        try OCRLanguages.configure(request, languages: languages)
        try VNImageRequestHandler(cgImage: image).perform([request])
        if isCancelled() { throw CancellationError() }
        var count = 0
        let blocks = try (request.results ?? []).compactMap { observation -> PDFTextBlock? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = clean(candidate.string).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            count += text.count
            guard count <= maximumCharacters else { throw BakerError(message: "Page \(pageNumber) exceeds the recognised text size limit.", code: .resourceLimit) }
            let b = observation.boundingBox
            return .init(text: text, bounds: CGRect(x: box.minX + b.minX * box.width, y: box.minY + b.minY * box.height, width: b.width * box.width, height: b.height * box.height), source: .vision)
        }
        return .init(pageNumber: pageNumber, pageSize: box.size, blocks: paragraphs(orderedLines(blocks)), source: .vision,
            warnings: blocks.isEmpty ? ["No text was found on this page. Figures and blank pages are not reproduced."] : ["Apple Vision OCR used a bounded page raster. Reading order and mathematical notation require review."])
    }

    private static func rasterise(_ page: PDFPage, box: CGRect) throws -> CGImage {
        let scale = min(2, min(4_096 / max(box.width, box.height), sqrt(8_000_000 / (box.width * box.height))))
        let width = max(1, Int(floor(box.width * scale))), height = max(1, Int(floor(box.height * scale)))
        guard width <= 4_096, height <= 4_096, width * height <= 8_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw BakerError(message: "The PDF page could not be rasterised within the memory limit.", code: .resourceLimit)
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
        context.translateBy(x: -box.minX, y: -box.minY)
        page.draw(with: .cropBox, to: context)
        guard let image = context.makeImage() else { throw BakerError(message: "The PDF page raster is unavailable.", code: .recognitionFailed) }
        return image
    }

    private static func splitColumns(_ line: PDFSelection, page: PDFPage, characterBoxes: [CGRect]) -> [(PDFSelection, CGRect)] {
        let lineBox = line.bounds(for: page)
        var low = 0, high = characterBoxes.count
        while low < high {
            let middle = (low + high) / 2
            if characterBoxes[middle].midY < lineBox.minY { low = middle + 1 } else { high = middle }
        }
        var boxes: [CGRect] = []
        var index = low
        while index < characterBoxes.count, characterBoxes[index].midY <= lineBox.maxY {
            let box = characterBoxes[index]
            if box.maxX > lineBox.minX && box.minX < lineBox.maxX { boxes.append(box) }
            index += 1
        }
        boxes.sort { $0.minX < $1.minX }
        var cuts: [CGFloat] = []
        var previous: CGRect?
        for box in boxes {
            if box.width > max(24, lineBox.height * 2.5) { cuts.append(box.midX) }
            if let prior = previous, box.minX - prior.maxX > max(24, lineBox.height * 2.5) { cuts.append((box.minX + prior.maxX) / 2) }
            previous = box
        }
        cuts = Array(Set(cuts.filter { $0 > lineBox.minX && $0 < lineBox.maxX })).sorted()
        guard !cuts.isEmpty else { return [(line, lineBox)] }
        let edges = [lineBox.minX] + cuts + [lineBox.maxX]
        let segments: [(PDFSelection, CGRect)] = zip(edges, edges.dropFirst()).compactMap { left, right in
            let clip = CGRect(x: left, y: lineBox.minY, width: right - left, height: lineBox.height)
            guard let selection = page.selection(for: clip) else { return nil }
            return (selection, selection.bounds(for: page).intersection(clip))
        }
        return segments.isEmpty ? [(line, lineBox)] : segments
    }

    private static func orderedLines(_ lines: [PDFTextBlock]) -> [PDFTextBlock] {
        let regions = lines.enumerated().map { PDFRegion(id: $0.offset, bounds: $0.element.bounds, content: .text($0.element.text)) }
        return PDFStructure.readingOrder(regions).map { lines[$0.id] }
    }

    private static func paragraphs(_ lines: [PDFTextBlock]) -> [PDFTextBlock] {
        var result: [PDFTextBlock] = []
        for line in lines {
            if let last = result.last {
                let gap = last.bounds.minY - line.bounds.maxY
                let height = max(line.bounds.height, 1)
                if last.headingLevel == nil, line.headingLevel == nil,
                   abs(last.bounds.minX - line.bounds.minX) < height, gap >= -height * 0.25, gap < height * 0.65 {
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
