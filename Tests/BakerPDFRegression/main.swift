import AppKit
import BakerCore
import CoreGraphics
import CoreText
import Foundation
import PDFKit

struct Failure: Error, CustomStringConvertible { let description: String }
var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw Failure(description: message) }
    checks += 1
}
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

func drawText(_ text: String, in context: CGContext, y: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.black]
    context.textPosition = CGPoint(x: 45, y: y)
    CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
}
func fixture(_ url: URL, pages: [[String]], raster: Bool = false) throws {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let consumer = CGDataConsumer(url: url as CFURL), let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else {
        throw Failure(description: "PDF fixture context")
    }
    for lines in pages {
        pdf.beginPDFPage(nil)
        if raster {
            guard let imageContext = CGContext(data: nil, width: 1224, height: 1584, bitsPerComponent: 8, bytesPerRow: 1224 * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure(description: "Raster context") }
            imageContext.setFillColor(CGColor(gray: 1, alpha: 1))
            imageContext.fill(CGRect(x: 0, y: 0, width: 1224, height: 1584))
            imageContext.scaleBy(x: 2, y: 2)
            for (index, line) in lines.enumerated() { drawText(line, in: imageContext, y: 700 - CGFloat(index) * 35) }
            pdf.draw(imageContext.makeImage()!, in: box)
        } else {
            for (index, line) in lines.enumerated() { drawText(line, in: pdf, y: 700 - CGFloat(index) * 35) }
        }
        pdf.endPDFPage()
    }
    pdf.closePDF()
}

func run() throws {
    let base = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? NSTemporaryDirectory() + "BakerPDFRegression", isDirectory: true)
    let root = base.appendingPathComponent("run-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("text-fixture.pdf")
    try fixture(source, pages: [["Baker PDF conversion", "Literal: # $ % & _ { } ~ ^ \\"], ["Second page: alpha α and beta β"]])
    let original = try Data(contentsOf: source)
    let markdown = root.appendingPathComponent("text-result.md")
    let report = try PDFConverter.convert(source: source, destination: markdown, format: .markdown)
    let text = try String(contentsOf: markdown, encoding: .utf8)
    try check(report.totalPages == 2 && report.ocrPages == 0, "Native text selected for both pages")
    try check(text.contains("Baker PDF conversion") && text.contains("Second page"), "Multipage text preserved")
    try check(text.contains("Page 1; source: textLayer") && text.contains("Page 2; source: textLayer"), "Page provenance")
    try check(text.contains("\\#") && text.contains("\\$") && text.contains("\\_"), "Markdown special characters escaped")
    try check(report.bytesWritten == Data(text.utf8).count, "Exact exported byte count")
    try check(!report.warnings.isEmpty && !report.pages[0].warnings.isEmpty, "Layout and semantic limitations reported")
    let latex = root.appendingPathComponent("text-result.tex")
    _ = try PDFConverter.convert(source: source, destination: latex, format: .latex)
    let tex = try String(contentsOf: latex, encoding: .utf8)
    try check(tex.contains("\\usepackage{fontspec}") && tex.hasSuffix("\\end{document}\n"), "Unicode LaTeX document framing")
    try check(tex.contains("\\newpage") && tex.contains("α"), "Page boundaries and Unicode preserved")
    try check(PDFConverter.escapeLaTeX("\\{}$&%#_^~") == "\\textbackslash{}\\{\\}\\$\\&\\%\\#\\_\\textasciicircum{}\\textasciitilde{}", "All LaTeX metacharacters escaped")
    try check(PDFConverter.escapeMarkdown(#"[x](y) `x` <b> $x$ \"#) == #"\[x\](y) \`x\` \<b\> \$x\$ \\"#, "Markdown injection characters escaped")
    let cancelled = root.appendingPathComponent("cancelled.md")
    let flag = CancellationFlag()
    do {
        _ = try PDFConverter.convert(source: source, destination: cancelled, format: .markdown, isCancelled: { flag.cancelled }, progress: {
            if $0.completedPages == 1 { flag.cancel() }
        })
        throw Failure(description: "Cancellation did not stop conversion")
    } catch is CancellationError { checks += 1 }
    try check(!FileManager.default.fileExists(atPath: cancelled.path), "Cancellation leaves no destination")
    let bounded = root.appendingPathComponent("bounded.md")
    var options = PDFConversionOptions()
    options.maximumOutputBytes = 50
    do { _ = try PDFConverter.convert(source: source, destination: bounded, format: .markdown, options: options); throw Failure(description: "Output limit ignored") }
    catch is BakerError { checks += 1 }
    try check(!FileManager.default.fileExists(atPath: bounded.path), "Output limit cleans partial file")
    options = .init()
    options.maximumPages = 1
    do { _ = try PDFConverter.convert(source: source, destination: bounded, format: .markdown, options: options); throw Failure(description: "Page limit ignored") }
    catch is BakerError { checks += 1 }
    options = .init()
    options.maximumPageCharacters = 1
    do { _ = try PDFConverter.convert(source: source, destination: bounded, format: .markdown, options: options); throw Failure(description: "Page text limit ignored") }
    catch is BakerError { checks += 1 }
    do { _ = try PDFConverter.convert(source: source, destination: markdown, format: .markdown); throw Failure(description: "Existing destination overwritten") }
    catch is BakerError { checks += 1 }
    try check(try String(contentsOf: markdown, encoding: .utf8) == text, "Existing file unchanged")
    try check(try Data(contentsOf: source) == original, "Source PDF unchanged")
    let corrupt = root.appendingPathComponent("corrupt.pdf")
    try Data("not a PDF".utf8).write(to: corrupt)
    do { _ = try PDFConverter.convert(source: corrupt, destination: bounded, format: .markdown); throw Failure(description: "Corrupt file accepted") }
    catch is BakerError { checks += 1 }
    let locked = root.appendingPathComponent("locked.pdf")
    let document = PDFDocument(url: source)!
    try check(document.write(to: locked, withOptions: [.userPasswordOption: "baker-test", .ownerPasswordOption: "baker-owner"]), "Encrypted fixture written")
    try check(PDFDocument(url: locked)?.isLocked == true, "Encrypted fixture locked")
    do { _ = try PDFConverter.convert(source: locked, destination: bounded, format: .markdown); throw Failure(description: "Locked PDF accepted") }
    catch is BakerError { checks += 1 }
    let scanned = root.appendingPathComponent("scanned-fixture.pdf")
    try fixture(scanned, pages: [["Baker scanned document", "Vision reads this page"]], raster: true)
    try check(PDFDocument(url: scanned)?.page(at: 0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false, "Scanned fixture has no text layer")
    let ocrURL = root.appendingPathComponent("scanned-result.md")
    let ocr = try PDFConverter.convert(source: scanned, destination: ocrURL, format: .markdown)
    let recognised = try String(contentsOf: ocrURL, encoding: .utf8)
    try check(ocr.ocrPages == 1 && recognised.lowercased().contains("baker scanned document"), "Real Vision fallback recognises raster page")
    try check(recognised.contains("source: vision"), "OCR provenance retained")
    let blank = root.appendingPathComponent("blank-fixture.pdf")
    try fixture(blank, pages: [[]])
    let blankReport = try PDFConverter.convert(source: blank, destination: root.appendingPathComponent("blank-result.md"), format: .markdown)
    try check(blankReport.pages[0].characterCount == 0 && blankReport.warnings.contains(where: { $0.contains("No text was found") }), "Blank page remains explicit without invented text")
    try check(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".baker-pdf-") }, "No temporary output files remain")
    print("Baker PDF regression: \(checks) checks passed. Fixtures and exports: \(root.path)")
}

do { try run() } catch { fputs("Baker PDF regression failed: \(error)\n", stderr); exit(1) }
