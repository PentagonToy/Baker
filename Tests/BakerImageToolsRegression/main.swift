import AppKit
import ImageIO

var checks = 0
func check(_ value: Bool, _ message: String) { precondition(value, message); checks += 1 }
func rejects(_ message: String, _ operation: () throws -> Void) {
    do { try operation(); fatalError(message) } catch { checks += 1 }
}
func pixels(_ image: CGImage) -> [UInt8] {
    var values = [UInt8](repeating: 0, count: image.width * image.height * 4)
    values.withUnsafeMutableBytes { buffer in
        let c = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        c.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return values
}
func fixture() -> CGImage {
    let c = CGContext(data: nil, width: 96, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 96, height: 64))
    c.setFillColor(CGColor(red: 0, green: 0.45, blue: 0.7, alpha: 1)); c.fill(CGRect(x: 12, y: 16, width: 24, height: 20))
    c.setFillColor(CGColor(gray: 0, alpha: 1)); c.fill(CGRect(x: 60, y: 44, width: 1, height: 1))
    return c.makeImage()!
}
func writePNG(_ image: CGImage, _ url: URL) {
    let writer = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, image, nil); precondition(CGImageDestinationFinalize(writer))
}
let svgText = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"96\" height=\"64\" viewBox=\"0 0 96 64\"><path d=\"M12 16h24v20H12Z\" fill=\"#0072B2\"/></svg>"
@MainActor func wait(_ editor: CaptureEditorState) async throws {
    for _ in 0..<1200 { if !editor.processing { return }; try await Task.sleep(nanoseconds: 10_000_000) }
    fatalError("Editor did not finish")
}
@MainActor func run() async throws {
    let output = URL(fileURLWithPath: CommandLine.arguments[1]), toolDir = URL(fileURLWithPath: CommandLine.arguments[2])
    let tools = ImageVectorTools(python: URL(fileURLWithPath: CommandLine.arguments[3]), worker: URL(fileURLWithPath: CommandLine.arguments[4]), directory: toolDir)
    let source = fixture(), before = pixels(source)
    let alpha = try ImageBackgroundRemoval.remove(source, mode: .paper), transparent = pixels(alpha)
    check(alpha.width == 96 && alpha.height == 64, "Background removal keeps dimensions")
    check(transparent[3] == 0, "White paper becomes transparent")
    check(stride(from: 3, to: before.count, by: 4).contains { transparent[$0] == 255 && before[$0] == 255 }, "Foreground remains opaque")
    check(pixels(source) == before, "Background removal never mutates original")
    let blank = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    blank.setFillColor(CGColor(gray: 1, alpha: 1)); blank.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    rejects("Blank background is not a usable cutout") { _ = try ImageBackgroundRemoval.remove(blank.makeImage()!, mode: .paper) }
    let antialias = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    antialias.setFillColor(CGColor(gray: 1, alpha: 1)); antialias.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    antialias.setFillColor(CGColor(gray: 0.5, alpha: 1)); antialias.fill(CGRect(x: 4, y: 4, width: 8, height: 8))
    let edgeSource = antialias.makeImage()!, edgeBefore = pixels(edgeSource), edgeAfter = pixels(try ImageBackgroundRemoval.remove(edgeSource, mode: .paper))
    check(stride(from: 0, to: edgeBefore.count, by: 4).allSatisfy { abs(Int(edgeAfter[$0]) + 255 - Int(edgeAfter[$0 + 3]) - Int(edgeBefore[$0])) <= 1 }, "Antialiased edges recompose on white without halos")
    let vector = try CaptureSVG(data: Data(svgText.utf8))
    check(vector.width == 96 && vector.height == 64, "SVG dimensions validated")
    let preview = try vector.raster(maximumPixelSize: 48)
    check(preview.width == 48 && preview.height == 32, "SVG thumbnail is bounded")
    let full = try vector.raster(maximumPixelSize: 96)
    check(pixels(full).contains { $0 != 0 }, "SVG preview renders visible paths")
    for bad in [svgText.replacingOccurrences(of: "<path", with: "<script"), svgText.replacingOccurrences(of: "fill=", with: "onclick="),
        svgText.replacingOccurrences(of: "#0072B2", with: "url(https://example.invalid/a)"), "<!DOCTYPE svg [<!ENTITY x 'bad'>]>" + svgText,
        svgText.replacingOccurrences(of: "96\" height", with: "999999\" height"), svgText.replacingOccurrences(of: "<path", with: "<image")] {
        rejects("Unsafe or invalid SVG must fail") { _ = try CaptureSVG(data: Data(bad.utf8)) }
    }
    var generated = [ImageVectorMode: CaptureSVG]()
    for mode in ImageVectorMode.allCases {
        let data = try ImageVectoriser.convert(source, mode: mode, tools: tools), svg = try CaptureSVG(data: data)
        generated[mode] = svg
        check(svg.width == 96 && svg.height == 64, "Actual trace retains pixel dimensions")
        check(!String(decoding: data, as: UTF8.self).contains("<image"), "Trace contains no embedded bitmap")
        try data.write(to: output.appendingPathComponent(mode == .colour ? "colour.svg" : "monochrome.svg"))
        writePNG(try svg.raster(maximumPixelSize: 96), output.appendingPathComponent(mode == .colour ? "colour-preview.png" : "monochrome-preview.png"))
    }
    let bw = pixels(try generated[.monochrome]!.raster(maximumPixelSize: 96))
    let dot = stride(from: 0, to: before.count, by: 4).first { before[$0] < 10 && before[$0 + 1] < 10 && before[$0 + 2] < 10 }!
    check(bw[dot + 3] > 0, "Monochrome tracing retains a single-pixel mark")
    let clearTrace = try CaptureSVG(data: ImageVectoriser.convert(alpha, mode: .colour, tools: tools))
    check(pixels(try clearTrace.raster(maximumPixelSize: 96))[3] == 0, "Colour tracing preserves removed background transparency")
    let archiveDir = output.appendingPathComponent("archive-" + UUID().uuidString)
    let input = output.appendingPathComponent("source.png"), svgFile = output.appendingPathComponent("replacement.svg")
    writePNG(source, input); try vector.data.write(to: svgFile)
    let archive = try CaptureArchive(directory: archiveDir), record = try archive.add(source: input)
    let oldURL = archive.fileURL(for: record), pngBytes = try Data(contentsOf: oldURL)
    let badSVG = output.appendingPathComponent("invalid.svg")
    try Data("<svg><script/></svg>".utf8).write(to: badSVG)
    rejects("Failed conversion preserves original") { _ = try archive.replace(source: badSVG, record: record) }
    check(try Data(contentsOf: oldURL) == pngBytes && archive.records == [record], "Rejected SVG leaves PNG and history unchanged")
    let saved = try archive.replace(source: svgFile, record: record)
    check(saved.id == record.id && saved.createdAt == record.createdAt && saved.isVector, "Vector replaces same capture identity")
    check((saved.fileName as NSString).deletingPathExtension == (record.fileName as NSString).deletingPathExtension, "SVG conversion preserves typed filename stem")
    check(!FileManager.default.fileExists(atPath: oldURL.path), "PNG removed after SVG commit")
    check(try Data(contentsOf: archive.fileURL(for: saved)) == vector.data, "Only SVG bytes stored")
    check(try CaptureArchive(directory: archiveDir).records == [saved], "SVG survives history reload")
    _ = try archive.thumbnail(for: saved); checks += 1
    let raster = try archive.original(for: saved)
    let edited = output.appendingPathComponent("edited.png"); writePNG(raster, edited)
    let again = try archive.replace(source: edited, record: saved)
    check(!again.isVector && !FileManager.default.fileExists(atPath: archive.fileURL(for: saved).path), "Done after raster editing replaces SVG with one PNG")
    check(try Data(contentsOf: input) == pngBytes, "Caller-owned input is never deleted")
    // Reproduce both sides of a crash between file creation, index commit and old-file removal.
    let freshSVG = try archive.replace(source: svgFile, record: again)
    try pngBytes.write(to: archive.fileURL(for: again))
    let journal = archiveDir.appendingPathComponent(".baker-replacement.json")
    try JSONSerialization.data(withJSONObject: ["old": JSONSerialization.jsonObject(with: JSONEncoder().encode(again)), "new": JSONSerialization.jsonObject(with: JSONEncoder().encode(freshSVG))]).write(to: journal)
    _ = try CaptureArchive(directory: archiveDir)
    check(!FileManager.default.fileExists(atPath: archive.fileURL(for: again).path), "Committed recovery removes obsolete PNG")
    let uncommitted = CaptureRecord(id: freshSVG.id, createdAt: freshSVG.createdAt, fileName: again.fileName, pixelWidth: 96, pixelHeight: 64)
    try pngBytes.write(to: archive.fileURL(for: uncommitted))
    try JSONSerialization.data(withJSONObject: ["old": JSONSerialization.jsonObject(with: JSONEncoder().encode(freshSVG)), "new": JSONSerialization.jsonObject(with: JSONEncoder().encode(uncommitted))]).write(to: journal)
    _ = try CaptureArchive(directory: archiveDir)
    check(!FileManager.default.fileExists(atPath: archive.fileURL(for: uncommitted).path) && FileManager.default.fileExists(atPath: archive.fileURL(for: freshSVG).path), "Uncommitted recovery keeps original SVG")
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("baker-svg-test-" + UUID().uuidString))
    defer { pasteboard.releaseGlobally() }
    let copy = SVGCopyProbe(ClipboardCoordinator(pasteboard: pasteboard, prepareImage: { _ in fatalError("SVG must not enter raster clipboard encoding") }))
    check(await copy.copyImageFile(archive.fileURL(for: freshSVG)), "SVG copy succeeds through production output method")
    let types = pasteboard.types ?? []
    check(types.contains(.fileURL) && !types.contains(.png) && !types.contains(.tiff), "SVG clipboard contains the file without PNG or TIFF")
    let copied = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
    check(copied == [archive.fileURL(for: freshSVG)], "Clipboard points to the single SVG file")
    let store = CaptureStore(directory: output.appendingPathComponent("store-" + UUID().uuidString))
    let stored = try await store.add(file: input)
    try await store.saveFormula(SavedFormula(id: stored.record.id, originalLatex: "x", latex: "x", unicodeOverride: nil, model: "test", confidenceMethod: nil, confidence: nil, diagnostics: nil, format: "latex", style: "bare"))
    let changed = try await store.replace(vector: vector, record: stored.record)
    let metadata = try await store.savedFormulas(), loadedVector = try await store.vector(changed.record)
    check(changed.record.isVector && metadata.isEmpty && loadedVector.data == vector.data, "Actor save removes stale OCR and reloads SVG")
    let editor = CaptureEditorState(image: source)
    editor.add(CaptureMark(tool: .rectangle, points: [.zero, CGPoint(x: 48, y: 64)], colour: .white, width: 1, filled: true))
    editor.vectorise(.monochrome, tools: tools); try await wait(editor)
    check(editor.vector != nil && editor.error == nil && !editor.canDraw, "Vectorise changes current document and disables raster tools")
    let masked = pixels(try editor.vector!.raster(maximumPixelSize: 96))
    check(masked[(20 * 96 + 20) * 4 + 3] == 0, "Masked original pixels do not appear in traced SVG")
    editor.undo(); check(editor.vector == nil && editor.marks.count == 1 && editor.canDraw, "Undo restores raster with mask")
    editor.redo(); check(editor.vector != nil && editor.marks.isEmpty, "Redo restores SVG document")
    editor.reset(); check(try editor.vector == nil && pixels(editor.rendered()) == before, "Reset restores source pixels")
    editor.removeBackground(.paper); try await wait(editor)
    check(try editor.error == nil && pixels(editor.rendered())[3] == 0, "Editor commits transparent background operation")
    editor.undo(); check(pixels(try editor.rendered()) == before, "Background Undo restores original")
    editor.add(CaptureMark(tool: .crop, points: [.zero, CGPoint(x: 48, y: 32)], colour: .white, width: 1))
    editor.vectorise(.colour, tools: tools); try await wait(editor)
    check(editor.vector?.width == 48 && editor.vector?.height == 32, "Vector conversion uses the current crop")
    editor.undo(); check(editor.marks.last?.tool == .crop && editor.pixelSize.width == 96, "Undo restores source geometry and crop")
    editor.reset()
    editor.removeBackground(.paper); editor.cancelProcessing(); try await wait(editor)
    check(pixels(try editor.rendered()) == before, "Cancelled operation cannot replace document")
    let reopened = CaptureEditorState(image: try freshSVG.isVector ? vector.raster(maximumPixelSize: 96) : source)
    check(reopened.vector == nil && reopened.canDraw, "Reopened vector is an editable in-memory raster")
    check(FileManager.default.fileExists(atPath: archive.fileURL(for: freshSVG).path), "Opening for editing has not changed SVG on disk")
    print("Passed \(checks) image-tool and single-file document checks")
}
Task { @MainActor in do { try await run(); exit(0) } catch { print(error); exit(1) } }
dispatchMain()
