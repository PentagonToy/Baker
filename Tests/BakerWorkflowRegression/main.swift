import AppKit
import Foundation

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return storage }
    func set() { lock.lock(); storage = true; lock.unlock() }
}
@MainActor func run() async throws {
    var checks = 0
    func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); checks += 1 }
    func wait(_ flag: Flag) async {
        let deadline = Date().addingTimeInterval(5)
        while !flag.value { precondition(Date() < deadline, "Worker did not start"); await Task.yield() }
    }
    let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("library-" + UUID().uuidString)
    let previewStore = CaptureStore(directory: root.appendingPathComponent("preview-fixture"))
    let large = CGContext(data:nil,width:4096,height:1024,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
    let largeRecord = try await previewStore.add(image: large.makeImage()!).record
    let displayPreview = try await previewStore.preview(largeRecord)
    check(displayPreview.width == 2048 && displayPreview.height == 512, "Display preview bounds the decoded image and preserves aspect ratio")
    let full = try await previewStore.original(largeRecord)
    check(full.width == 4096 && full.height == 1024, "Display optimisation leaves original pixels intact")
    let library = CaptureLibrary(directory: root)
    let context = CGContext(data:nil,width:96,height:48,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(gray:0.9,alpha:1));context.fill(CGRect(x:0,y:0,width:96,height:48))
    var captures: [StoredCapture] = []
    for _ in 0..<8 { captures.append(try await library.store.add(image: context.makeImage()!)) }
    for capture in captures { _ = try await library.thumbnail(capture.record, protecting: []) }
    check(captures.filter { library.cachedThumbnail($0.record.id) != nil }.count == 6, "Library cache retains six images")
    let a = Task { try await library.thumbnail(captures[0].record, protecting: []) }
    let b = Task { try await library.thumbnail(captures[0].record, protecting: []) }
    let first = try await a.value, second = try await b.value
    check(first === second, "Concurrent thumbnails share the cached image")
    func formula(_ index: Int) -> SavedFormula {
        SavedFormula(id:captures[index].record.id,originalLatex:"x",latex:"x",unicodeOverride:nil,model:"fixture",confidenceMethod:nil,confidence:nil,diagnostics:nil,format:"LaTeX",style:LatexCopyStyle.bare.rawValue,savedAt:Date(timeIntervalSince1970:Double(index+100)))
    }
    let one = library.enqueue(.save(formula(0),limit:8,days:0))
    let two = library.enqueue(.save(formula(1),limit:8,days:0))
    let keep = library.enqueue(.retain(limit:1,days:0))
    _ = try await one.value; _ = try await two.value
    let kept = try await keep.value
    check(kept.count == 1 && kept[captures[1].record.id] != nil, "History writes and retention keep enqueue order")
    _ = try await library.enqueue(.clear).value
    await library.flushHistory()
    let cleared = try await library.store.savedFormulas()
    check(cleared.isEmpty, "Clear waits behind earlier history writes")
    let other = CaptureStore(directory: root.appendingPathComponent("other"))
    library.use(other)
    check(library.cachedThumbnail(captures[0].record.id) == nil, "Switching stores clears old images")
    let request = RecognitionRequest(url:root,formula:true,python:"",configuration:"",languages:["ko-KR","en-US"],finnish:false,tesseract:"")
    let recognition = RecognitionCoordinator(recogniser: { request in FormulaRecognition(latex:"x_2",confidence:nil,model:String(request.languages.count)) },renderer:{ _ in NSImage(size:NSSize(width:30,height:20)) })
    let response = try await recognition.recognise(request)
    check(response.latex == "x_2" && response.model == "2", "Recognition forwards its request and result")
    let rendered = try await recognition.render("x_2")
    check(rendered.size == NSSize(width:30,height:20), "Preview uses injected renderer")
    let started = Flag()
    let slow = RecognitionCoordinator(recogniser: { _ in
        started.set();while !Task.isCancelled { Thread.sleep(forTimeInterval:0.002) };throw CancellationError()
    },renderer:{ _ in try await Task.sleep(nanoseconds:2_000_000_000);return NSImage(size:.zero) })
    let pending = Task { try await slow.recognise(request) }
    await wait(started)
    do { _ = try await slow.recognise(request);check(false,"Concurrent recognition accepted") }
    catch let failure as BakerError { check(failure.code == .invalidState, "Concurrent recognition rejected") }
    pending.cancel();await slow.close()
    do { _ = try await pending.value;check(false,"Recognition cancellation lost") } catch is CancellationError { check(true,"Recognition cancellation propagated") }
    let preview = Task { try await slow.render("x") }
    await Task.yield();preview.cancel();await slow.close()
    do { _ = try await preview.value;check(false,"Preview cancellation lost") } catch is CancellationError { check(true,"Preview cancellation propagated") }
    let documentStarted = Flag()
    let documents = DocumentCoordinator(converter: { source,destination,format,_,progress in
        if source.lastPathComponent == "cancel.pdf" {
            documentStarted.set();while !Task.isCancelled { Thread.sleep(forTimeInterval:0.002) }
            progress(PDFConversionProgress(pageNumber:1,totalPages:1,phase:.completed,message:"late"))
            throw CancellationError()
        }
        progress(PDFConversionProgress(pageNumber:1,totalPages:1,phase:.completed,message:"ready"))
        return PDFConversionReport(destination:destination,format:format,pages:[],bytesWritten:0,warnings:[])
    })
    var updates = 0
    let document = Task { try await documents.convert(source:root.appendingPathComponent("cancel.pdf"),destination:root.appendingPathComponent("out.md"),format:.markdown,options:PDFConversionOptions()) { _ in updates += 1 } }
    await wait(documentStarted)
    do { _ = try await documents.convert(source:root,destination:root,format:.markdown,options:PDFConversionOptions()) { _ in };check(false,"Concurrent document accepted") }
    catch let failure as BakerError { check(failure.code == .invalidState,"Concurrent document rejected") }
    documents.cancel();let before = updates;await documents.close()
    do { _ = try await document.value;check(false,"Document cancellation lost") } catch is CancellationError { check(true,"Document cancellation propagated") }
    try await Task.sleep(nanoseconds:10_000_000)
    check(updates == before,"Cancelled document cannot publish late progress")
    let next = try await documents.convert(source:root.appendingPathComponent("next.pdf"),destination:root.appendingPathComponent("next.md"),format:.markdown,options:PDFConversionOptions()) { _ in }
    check(next.destination.lastPathComponent == "next.md","Document worker resets after cancellation")
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let prepareStarted = Flag(), releasePrepare = Flag()
    let clipboard = ClipboardCoordinator(pasteboard:pasteboard,prepareImage:{ url in
        prepareStarted.set();while !releasePrepare.value { Thread.sleep(forTimeInterval:0.002) }
        return try ImageClipboard.prepare(imageURL:url)
    })
    let imageURL = root.appendingPathComponent(captures[0].record.fileName)
    let copying = Task { try await clipboard.copyImage(imageURL) }
    await wait(prepareStarted)
    try clipboard.copyText("newer text")
    releasePrepare.set()
    let imageCopied = try await copying.value
    check(imageCopied == false,"Old image request cannot replace newer text")
    check(pasteboard.string(forType:.string) == "newer text","Text clipboard survives superseded image preparation")
    try clipboard.copyMath("x′",font:.stixTwo)
    check(pasteboard.string(forType:.string) == "x′" && pasteboard.data(forType:.rtf) != nil,"Math clipboard preserves text and RTF")
    for flag in [true,false] {
        check(CaptureHistoryFilter.all.includes(formula:flag),"All filter includes both capture types")
        check(CaptureHistoryFilter.formulas.includes(formula:flag) == flag,"Formula filter")
        check(CaptureHistoryFilter.images.includes(formula:flag) != flag,"Image filter")
    }
    check(BakerMotion.selection(reduced:true) == nil,"Reduced motion disables state transitions")
    let exports = FileExportCoordinator()
    let destination = root.appendingPathComponent("copied.png")
    try await exports.save(source: imageURL, destination: destination)
    let originalBytes = try Data(contentsOf: imageURL)
    let copiedBytes = try Data(contentsOf: destination)
    check(copiedBytes == originalBytes, "File export preserves bytes")
    try Data("old".utf8).write(to: destination)
    try await exports.save(source: imageURL, destination: destination)
    let replacedBytes = try Data(contentsOf: destination)
    check(replacedBytes == originalBytes, "File export replaces an existing destination")
    do { try await exports.save(source: imageURL, destination: imageURL); check(false,"Source overwrite accepted") }
    catch let error as BakerError { check(error.code == .invalidInput,"File export rejects source overwrite") }
    await exports.close()
    print("Workflow ownership: \(checks) checks passed")
}
Task { @MainActor in do { try await run();exit(0) } catch { print(error);exit(1) } }
dispatchMain()
