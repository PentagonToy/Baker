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

    func region(_ id: Int, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ content: PDFRegion.Content) -> PDFRegion {
        PDFRegion(id: id, bounds: CGRect(x: x, y: y, width: width, height: 12), content: content)
    }
    let columns = [region(4, 320, 650, 200, .text("right bottom")), region(0, 40, 750, 480, .heading("Title", level: 1)),
                   region(2, 40, 650, 200, .text("left bottom")), region(3, 320, 700, 200, .text("right top")), region(1, 40, 700, 200, .text("left top"))]
    try check(PDFStructure.readingOrder(columns).map(\.id) == [0, 1, 2, 3, 4], "Spanning title followed by complete left and right columns")
    let structured = PDFStructure.reconstruct([
        region(0, 40, 700, 160, .equation("x^{2}+y^{2}=z^{2}", label: nil)),
        region(1, 320, 700, 160, .equation("a=b", label: nil)),
        region(2, 215, 700, 25, .equationLabel("21a")),
        region(3, 495, 700, 25, .equationLabel("21b")),
        region(4, 40, 600, 200, .figure(path: "assets/plot.png", caption: nil)),
        region(5, 40, 580, 200, .caption("Fig. 1. Plot & units")),
        region(6, 320, 580, 200, .caption("Unmatched caption")),
        region(7, 320, 500, 200, .table([["Species", "Value"], ["H₂O", "—"], ["CO₂", "1.3"]]))])
    let structuredMD = PDFStructure.render(structured, format: .markdown)
    let structuredTEX = PDFStructure.render(structured, format: .latex)
    try check(structuredMD.contains(#"\tag{21a}"#) && structuredMD.contains(#"\tag{21b}"#), "Labels attach to spatially compatible equations across columns")
    try check(structured.count == 5 && structuredMD.contains("Unmatched caption"), "Consume attached labels/caption only; retain unmatched content")
    try check(structuredMD.contains("![](assets/plot.png)") && structuredTEX.contains(#"\includegraphics"#), "Shared figure representation reaches both exporters")
    try check(structuredMD.contains("| H₂O | — |") && structuredTEX.contains("H₂O & —"), "Table cell meaning and missing-value dash preserved")
    try check(structuredTEX.contains("Plot \\& units"), "Caption literal text escaped in LaTeX")
    let orphan = PDFStructure.reconstruct([region(0, 50, 50, 20, .equationLabel("9"))])
    try check(orphan.count == 1 && PDFStructure.render(orphan, format: .markdown).contains("9"), "Unassociated label is never dropped")
    let invalidPath = PDFStructure.render([region(0, 0, 0, 10, .figure(path: "../private.png", caption: "Retain caption"))], format: .latex)
    try check(!invalidPath.contains("includegraphics") && invalidPath.contains("Retain caption"), "Reject unowned asset paths without losing captions")


    let columnPDF = root.appendingPathComponent("columns.pdf")
    var media = CGRect(x: 0, y: 0, width: 612, height: 792)
    let consumer = CGDataConsumer(url: columnPDF as CFURL)!
    let context = CGContext(consumer: consumer, mediaBox: &media, nil)!
    context.beginPDFPage(nil)
    func draw(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat) {
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black])), context)
    }
    // Deliberately alternating PDF stream order; visual reading order must be column-aware.
    draw("A document spanning columns", 40, 740, 30)
    draw("Left first", 40, 680, 18); draw("Right first", 330, 680, 18)
    draw("Left second", 40, 640, 18); draw("Right second", 330, 640, 18)
    context.endPDFPage(); context.closePDF()
    let columnOutput = root.appendingPathComponent("columns.md")
    _ = try PDFConverter.convert(source: columnPDF, destination: columnOutput, format: .markdown)
    let columnText = try String(contentsOf: columnOutput)
    try check(columnText.contains("# A document spanning columns"), "Real native-PDF title recognised from typography")
    let leftEnd = columnText.range(of: "Left second")!, rightStart = columnText.range(of: "Right first")!
    try check(leftEnd.lowerBound < rightStart.lowerBound, "Real two-column PDF exports complete left column before right column")


    let package = root.appendingPathComponent("bundle-source")
    try FileManager.default.createDirectory(at: package.appendingPathComponent("assets"), withIntermediateDirectories: true)
    let packageMD = package.appendingPathComponent("document.md")
    try Data("![](assets/figure.png)\n".utf8).write(to: packageMD)
    let figureBytes = Data([1,2,3,4])
    try figureBytes.write(to: package.appendingPathComponent("assets/figure.png"))
    let savedMD = root.appendingPathComponent("saved.md")
    try PDFExportBundle.save(source: packageMD, destination: savedMD)
    let savedText = try String(contentsOf: savedMD)
    let ownership = root.appendingPathComponent("saved.md.baker-assets.json")
    let sidecar = try JSONDecoder().decode(String.self, from: Data(contentsOf: ownership))
    try check(savedText.contains("![](\(sidecar)/figure.png)") && !savedText.contains("![](assets/"), "Saved document references its owned figure sidecar")
    try check(try Data(contentsOf: root.appendingPathComponent(sidecar + "/figure.png")) == figureBytes, "Figure bytes survive export")
    try check(PDFExportBundle.filesForCopy(savedMD).count == 3, "Clipboard file payload includes the document, figures and ownership manifest")
    let resaved = root.appendingPathComponent("another name.md")
    try PDFExportBundle.save(source: savedMD, destination: resaved)
    try check(try String(contentsOf: resaved).contains("figure.png"), "Previously exported document can be saved with a new name")
    try FileManager.default.removeItem(at: ownership)
    do { try PDFExportBundle.save(source: packageMD, destination: savedMD); throw Failure(description: "Unowned sidecar overwritten") }
    catch is BakerError { checks += 1 }
    try check(try Data(contentsOf: root.appendingPathComponent(sidecar + "/figure.png")) == figureBytes, "Unowned sidecar conflict preserves existing assets")

    let source = root.appendingPathComponent("text-fixture.pdf")
    try fixture(source, pages: [["Baker PDF conversion", "Literal: # $ % & _ { } ~ ^ \\"], ["Second page: alpha α and beta β"]])

    if let python = ProcessInfo.processInfo.environment["BAKER_DOCUMENT_PYTHON"] {
        let stub = root.appendingPathComponent("document-stub.py")
        try #"""
import argparse,json,time
from pathlib import Path
p=argparse.ArgumentParser()
for key in ('source','output','config'):p.add_argument('--'+key,required=True)
a=p.parse_args();cfg=json.loads(Path(a.config).read_text())
if cfg.get('sleep'):time.sleep(20)
o=Path(a.output);o.mkdir();(o/'assets').mkdir()
(o/'document.md').write_text('Structured contract output')
(o/'report.json').write_text(json.dumps({'pages':[{'page':i+1,'attached_labels':0,'unmatched_labels':[]} for i in range(cfg.get('pages',2))],'warnings':[]}))
"""#.write(to: stub, atomically: true, encoding: .utf8)
        let configuration = root.appendingPathComponent("stub-config.json")
        try Data("{}".utf8).write(to: configuration)
        var structuredOptions = PDFConversionOptions()
        structuredOptions.documentEngine = PDFDocumentEngine(python: URL(fileURLWithPath: python), worker: stub, configuration: configuration)
        let contractOutput = root.appendingPathComponent("contract.md")
        let contract = try PDFConverter.convert(source: source, destination: contractOutput, format: .markdown, options: structuredOptions)
        try check(contract.totalPages == 2 && contract.pages.allSatisfy { $0.source == .structured }, "Actual worker bridge decodes page provenance")
        try Data(#"{"pages":1}"#.utf8).write(to: configuration)
        let partial = root.appendingPathComponent("partial.md")
        do { _ = try PDFConverter.convert(source: source, destination: partial, format: .markdown, options: structuredOptions); throw Failure(description: "Partial structured document accepted") }
        catch is BakerError { checks += 1 }
        try check(!FileManager.default.fileExists(atPath: partial.path), "Partial worker report does not create an export")
        try Data(#"{"sleep":true}"#.utf8).write(to: configuration)
        let cancellation = CancellationFlag()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { cancellation.cancel() }
        let stopped = root.appendingPathComponent("worker-cancelled.md")
        do { _ = try PDFConverter.convert(source: source, destination: stopped, format: .markdown, options: structuredOptions, isCancelled: { cancellation.cancelled }); throw Failure(description: "Worker cancellation ignored") }
        catch is CancellationError { checks += 1 }
        try check(!FileManager.default.fileExists(atPath: stopped.path), "Cancelled document worker leaves no export")
    }

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
    if CommandLine.arguments.count > 2 {
        let corpus = URL(fileURLWithPath: CommandLine.arguments[2])
        let documentConfiguration = ProcessInfo.processInfo.environment["BAKER_DOCUMENT_CONFIGURATION"]
        let formats = documentConfiguration == nil ? PDFExportFormat.allCases : [.markdown]
        for format in formats {
            let destination = base.appendingPathComponent("corpus-structure." + format.fileExtension)
            var options = PDFConversionOptions()
            if let documentConfiguration, let python = ProcessInfo.processInfo.environment["BAKER_DOCUMENT_PYTHON"],
               let worker = ProcessInfo.processInfo.environment["BAKER_DOCUMENT_WORKER"] {
                options.documentEngine = PDFDocumentEngine(python: URL(fileURLWithPath: python), worker: URL(fileURLWithPath: worker), configuration: URL(fileURLWithPath: documentConfiguration))
            }
            let report = try PDFConverter.convert(source: corpus, destination: destination, format: format, options: options)
            print("Corpus \(format.rawValue): \(report.totalPages) pages; \(report.bytesWritten) bytes; \(destination.path)")
        }
    }
    print("Baker PDF regression: \(checks) checks passed. Fixtures and exports: \(root.path)")
}

do { try run() } catch { fputs("Baker PDF regression failed: \(error)\n", stderr); exit(1) }
