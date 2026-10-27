import AppKit
import PDFKit

actor ScanTestGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { if !released { await withCheckedContinuation { continuation = $0 } } }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

func scanRegression() async throws {
    var checks = 0
    func check(_ value: Bool, _ label: String) { precondition(value, label); checks += 1 }
    let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("scan-" + UUID().uuidString)
    let store = try ScanDocument(directory: root.appendingPathComponent("draft"))
    func image(_ gray: CGFloat) -> CGImage {
        let c = CGContext(data: nil, width: 320, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        c.setFillColor(CGColor(gray: gray, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 320, height: 200)); return c.makeImage()!
    }
    let options = try ScanOptions.decode("{\"delay\":2.5,\"searchable\":true}")
    check(options == ScanOptions(delay: 2.5, searchable: true), "CLI scan options retain fractional timing and searchable text")
    check(try ScanOptions.decode("{\"searchable\":false}") == ScanOptions(searchable: false), "Searchable text can be explicitly disabled")
    for text in ["{}", "{\"delay\":0}", "{\"delay\":61}", "{\"delay\":true}", "{\"searchable\":1}", "{\"delai\":3}"] {
        do { _ = try ScanOptions.decode(text); preconditionFailure("Invalid scan configuration must fail") }
        catch { checks += 1 }
    }
    do { try ScanOptions(delay: .infinity).validate(); preconditionFailure("Infinite delay must fail") }
    catch { checks += 1 }
    func size(_ page: ScanPage) throws -> Int64 { try (FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("draft/" + page.fileName).path)[.size] as! NSNumber).int64Value }
    let a = try await store.append(image(0.2))!
    let b = try await store.append(image(0.6))!
    let duplicate = try await store.append(image(0.6), rejectDuplicate: true)
    let countAfterDuplicate = await store.pages().count
    check(try await store.storageBytes() == size(a) + size(b), "Storage budget counts committed page files without duplicate writes")
    check(duplicate == nil && countAfterDuplicate == 2, "Automatic duplicate pauses without writing a page")
    let manual = try await store.append(image(0.6))!
    check((await store.pages()).count == 3, "Manual capture preserves intentionally identical pages")
    let retaken = try await store.append(image(0.9), replacing: b.id)!
    check((await store.pages()).map(\.id) == [a.id, retaken.id, manual.id], "Retake keeps the page's position")
    check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("draft/" + b.fileName).path), "Committed retake removes only its old page file")
    check(try await store.storageBytes() == size(a) + size(retaken) + size(manual), "Retake replaces the old size in the storage budget")
    try await store.move(manual.id, by: -1)
    check((await store.pages()).map(\.id) == [a.id, manual.id, retaken.id], "Review changes the export order")
    try await store.remove(manual.id)
    let restored = try ScanDocument(directory: root.appendingPathComponent("draft"), resume: true)
    check((await restored.pages()).map(\.id) == [a.id, retaken.id], "Draft resumes with the saved order and selection")
    check(try await restored.storageBytes() == size(a) + size(retaken), "Reopening and removing pages preserve the storage budget")
    let thumbnail = try await restored.preview(a, maximum: 160)
    check(thumbnail.width <= 160 && thumbnail.height <= 160, "Preview decoding is bounded independently of originals")
    let output = root.appendingPathComponent("scan.pdf")
    try await restored.export(to: output, searchable: false, languages: [])
    let pdf = PDFDocument(url: output)!
    check(pdf.pageCount == 2, "PDF contains exactly the reviewed pages")
    check(pdf.page(at: 0)!.bounds(for: .mediaBox).width == 160, "PDF preserves the source aspect ratio")
    let original = try Data(contentsOf: output)
    do { try await restored.export(to: output, searchable: false, languages: []); preconditionFailure("Must not overwrite without permission") }
    catch let error as BakerError { check(error.code == .storageConflict, "CLI-style exports refuse an existing destination") }
    check(try Data(contentsOf: output) == original, "Rejected export preserves the existing PDF")
    try await restored.export(to: output, searchable: false, languages: [], replace: true)
    check(PDFDocument(url: output)?.pageCount == 2, "Confirmed replacement publishes a complete PDF")
    let beforeCancellation = try Data(contentsOf: output)
    let gate = ScanTestGate()
    let cancelled = Task {
        await gate.wait()
        try await restored.export(to: output, searchable: false, languages: [], replace: true)
    }
    cancelled.cancel(); await gate.release()
    do { try await cancelled.value; preconditionFailure("Cancelled export must fail") }
    catch is CancellationError { check(try Data(contentsOf: output) == beforeCancellation, "Cancelled export cannot replace a saved PDF") }
    // A missing source page must not replace a previously complete PDF.
    try FileManager.default.removeItem(at: root.appendingPathComponent("draft/" + retaken.fileName))
    let complete = try Data(contentsOf: output)
    do { try await restored.export(to: output, searchable: false, languages: [], replace: true); preconditionFailure("Missing page must fail") }
    catch { check(try Data(contentsOf: output) == complete, "Failed export preserves its destination") }
    check((await restored.pages()).count == 2, "Failed export retains the recoverable draft")
    let temp = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(".baker-scan-") }
    check(temp.isEmpty, "Failed export cleans its staging PDF")
    // Corrupted manifest paths must never escape the draft folder.
    let manifestURL = root.appendingPathComponent("draft/scan.json")
    var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
    var rows = manifest["pages"] as! [[String: Any]]; rows[0]["fileName"] = "../scan.pdf"; manifest["pages"] = rows
    try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
    do { _ = try ScanDocument(directory: root.appendingPathComponent("draft"), resume: true); preconditionFailure("Traversal must fail") }
    catch let error as BakerError { check(error.code == .invalidInput, "Recovery rejects a page path outside the draft") }
    try await store.discard()
    check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("draft").path), "Explicit discard removes its working pages")
    check(await store.storageBytes() == 0, "Discard releases storage accounting")
    do { _ = try await store.append(image(0)); preconditionFailure("Discarded session must stay closed") }
    catch { checks += 1 }
    if CommandLine.arguments.contains("--ocr") {
        let ocr = try ScanDocument(directory: root.appendingPathComponent("ocr-draft"))
        let c = CGContext(data: nil, width: 800, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 800, height: 240))
        c.textPosition = CGPoint(x: 30, y: 100)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Baker Scan Page", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 48, nil)]))
        CTLineDraw(line, c)
        _ = try await ocr.append(c.makeImage()!)
        let pdfURL = root.appendingPathComponent("searchable.pdf")
        try await ocr.export(to: pdfURL, searchable: true, languages: ["en-US"])
        check(PDFDocument(url: pdfURL)?.string?.contains("Baker Scan Page") == true, "PDF contains searchable local OCR text")
        check((await ocr.pages()).count == 1, "Export itself keeps the draft until its owner confirms saving")
    }
    print("\(checks) scan draft and PDF checks passed")
}
Task {
    do { try await scanRegression(); exit(0) }
    catch { print("Scan regression failed: \(error)"); exit(1) }
}
dispatchMain()
