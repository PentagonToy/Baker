import BakerCore
import CoreGraphics
import Foundation
import ImageIO

struct RegressionFailure: Error, CustomStringConvertible { let description: String }
var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw RegressionFailure(description: message) }
    checks += 1
}
func rejects(_ message: String, _ operation: () throws -> Void) throws {
    do { try operation() } catch is RegressionFailure { throw RegressionFailure(description: message + ": unexpected regression error") }
    catch { checks += 1; return }
    throw RegressionFailure(description: message + ": operation unexpectedly succeeded")
}
func image(_ width: Int, _ height: Int) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.12, green: 0.3, blue: 0.7, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}
func write(_ image: CGImage, to url: URL, type: String = "public.png", count: Int = 1) throws {
    guard let target = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, count, nil) else { throw RegressionFailure(description: "Image destination unavailable: " + type) }
    for _ in 0..<count { CGImageDestinationAddImage(target, image, nil) }
    guard CGImageDestinationFinalize(target) else { throw RegressionFailure(description: "Fixture encoding failed: " + type) }
}
func files(_ directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
}
func writeIndex(_ records: [CaptureRecord], to directory: URL, version: Int = 1) throws {
    struct Index: Codable { let version: Int; let records: [CaptureRecord] }
    try JSONEncoder().encode(Index(version: version, records: records)).write(to: directory.appendingPathComponent(CaptureArchive.indexFileName))
}
func alteredPNG(_ url: URL, width: UInt32, height: UInt32) throws -> Data {
    var data = try Data(contentsOf: url)
    func replace(_ value: UInt32, at offset: Int) {
        data.replaceSubrange(offset..<(offset + 4), with: [UInt8(value >> 24), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)])
    }
    replace(width, at: 16); replace(height, at: 20)
    var crc: UInt32 = 0xffffffff
    for byte in data[12..<29] {
        crc ^= UInt32(byte)
        for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) }
    }
    replace(crc ^ 0xffffffff, at: 29)
    return data
}

func run() throws {
    guard CommandLine.arguments.count == 2 else { throw RegressionFailure(description: "Pass a fresh evidence directory outside source.") }
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    guard !FileManager.default.fileExists(atPath: root.path) else { throw RegressionFailure(description: "Evidence directory must not already exist.") }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("source.PNG")
    try write(image(1200, 800), to: source)
    let original = try Data(contentsOf: source)
    let directory = root.appendingPathComponent("archive", isDirectory: true)
    let archive = try CaptureArchive(directory: directory)
    try check(archive.records.isEmpty, "Missing index starts an empty archive")
    let first = try archive.add(source: source)
    try check(first.pixelWidth == 1200 && first.pixelHeight == 800, "Image metadata preserved")
    try check(first.fileName == first.id.uuidString.lowercased() + ".png", "Generated normalised filename")
    try check(try Data(contentsOf: source) == original, "Import preserves source")
    try check(try Data(contentsOf: archive.fileURL(for: first)) == original, "Import preserves encoded bytes")
    try check(archive.fileURL(for: first) != source, "Archive owns a separate durable file")
    let thumbnail = try archive.thumbnail(for: first)
    try check(thumbnail.width == 600 && thumbnail.height == 400, "Default thumbnail downsamples to 600px")
    let small = try archive.thumbnail(for: first, maximumPixelSize: 120)
    try check(small.width == 120 && small.height == 80, "Thumbnail bound follows requested size")
    try rejects("Invalid thumbnail request") { _ = try archive.thumbnail(for: first, maximumPixelSize: 601) }
    try rejects("Zero thumbnail request") { _ = try archive.thumbnail(for: first, maximumPixelSize: 0) }
    let second = try archive.add(source: source)
    try check(first.id != second.id && first.fileName != second.fileName, "Repeated import does not overwrite prior capture")
    try check(archive.records == [second, first], "Newest capture first")
    let reopened = try CaptureArchive(directory: directory)
    try check(reopened.records == archive.records, "Index survives reopening with exact metadata")
    try check(try Data(contentsOf: reopened.fileURL(for: first)) == original, "Image survives reopening")

    let jpeg = root.appendingPathComponent("misleading-extension.png")
    try write(image(160, 100), to: jpeg, type: "public.jpeg")
    let jpegRecord = try archive.add(source: jpeg)
    try check(jpegRecord.fileName.hasSuffix(".jpg"), "ImageIO format controls extension rather than source name")
    for (type, suffix) in [("public.tiff", "tiff"), ("com.microsoft.bmp", "bmp"), ("public.heic", "heic")] {
        let fixture = root.appendingPathComponent("source." + suffix)
        try write(image(160, 100), to: fixture, type: type)
        let record = try archive.add(source: fixture)
        try check(record.fileName.hasSuffix("." + suffix), "Retains supported source format " + suffix)
        try check(try Data(contentsOf: archive.fileURL(for: record)) == Data(contentsOf: fixture), "Copies source bytes " + suffix)
    }
    let beforeInvalid = try files(directory)
    let bad = root.appendingPathComponent("invalid.png")
    try Data("not an image".utf8).write(to: bad)
    try rejects("Malformed image") { _ = try archive.add(source: bad) }
    let animated = root.appendingPathComponent("animated.tiff")
    try write(image(16, 16), to: animated, type: "public.tiff", count: 2)
    try rejects("Multipage image") { _ = try archive.add(source: animated) }
    let wide = root.appendingPathComponent("wide.png")
    try alteredPNG(source, width: 8193, height: 1).write(to: wide)
    try rejects("Dimension metadata rejected without allocating full image") { _ = try archive.add(source: wide) }
    let large = root.appendingPathComponent("large.png")
    try alteredPNG(source, width: 6000, height: 6000).write(to: large)
    try rejects("32MP bound rejected from metadata") { _ = try archive.add(source: large) }
    try check(try files(directory) == beforeInvalid, "Rejected inputs leave archive files and index unchanged")

    let changedIndex = directory.appendingPathComponent(CaptureArchive.indexFileName)
    let validIndex = try Data(contentsOf: changedIndex)
    try Data("corrupt index".utf8).write(to: changedIndex)
    let corruptBefore = try files(directory)
    try rejects("Corrupt index fails visibly on reopen") { _ = try CaptureArchive(directory: directory) }
    try rejects("Externally changed index rolls back new copy") { _ = try archive.add(source: source) }
    try check(try files(directory) == corruptBefore, "Transaction rollback leaves no new capture or staging directory")
    try check(try Data(contentsOf: changedIndex) == Data("corrupt index".utf8), "Corrupt index is preserved rather than replaced")
    try check(try Data(contentsOf: source) == original, "Rollback preserves original source")
    try validIndex.write(to: changedIndex)
    try check(try CaptureArchive(directory: directory).records == archive.records, "Previous valid history remains recoverable")

    let traversal = root.appendingPathComponent("traversal", isDirectory: true)
    try FileManager.default.createDirectory(at: traversal, withIntermediateDirectories: true)
    let unsafe = CaptureRecord(id: UUID(), createdAt: Date(), fileName: "../source.PNG", pixelWidth: 1200, pixelHeight: 800)
    try writeIndex([unsafe], to: traversal)
    try rejects("Traversal index rejected") { _ = try CaptureArchive(directory: traversal) }
    try check(archive.fileURL(for: unsafe).deletingLastPathComponent() == archive.directory, "Public URL helper cannot traverse outside archive")
    let duplicate = root.appendingPathComponent("duplicate", isDirectory: true)
    try FileManager.default.createDirectory(at: duplicate, withIntermediateDirectories: true)
    try writeIndex([first, first], to: duplicate)
    try rejects("Duplicate identifiers rejected") { _ = try CaptureArchive(directory: duplicate) }
    try writeIndex([first], to: duplicate, version: 2)
    try rejects("Unknown index version rejected") { _ = try CaptureArchive(directory: duplicate) }

    let linked = root.appendingPathComponent("symlink", isDirectory: true)
    try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: linked.appendingPathComponent(CaptureArchive.indexFileName), withDestinationURL: changedIndex)
    try rejects("Symlink index rejected") { _ = try CaptureArchive(directory: linked) }
    try FileManager.default.removeItem(at: linked.appendingPathComponent(CaptureArchive.indexFileName))
    try writeIndex([first], to: linked)
    try FileManager.default.createSymbolicLink(at: linked.appendingPathComponent(first.fileName), withDestinationURL: source)
    try rejects("Symlink image rejected on reopen") { _ = try CaptureArchive(directory: linked) }

    let full = root.appendingPathComponent("full", isDirectory: true)
    try FileManager.default.createDirectory(at: full, withIntermediateDirectories: true)
    let entries = (0..<CaptureArchive.maximumRecords).map { index -> CaptureRecord in
        let id = UUID()
        return CaptureRecord(id: id, createdAt: Date(timeIntervalSince1970: Double(index)), fileName: id.uuidString.lowercased() + ".png", pixelWidth: 1, pixelHeight: 1)
    }
    try writeIndex(entries, to: full)
    let fullArchive = try CaptureArchive(directory: full)
    try check(fullArchive.records.count == CaptureArchive.maximumRecords, "Maximum-size history remains readable")
    let fullIndex = try Data(contentsOf: full.appendingPathComponent(CaptureArchive.indexFileName))
    try rejects("Archive limit refuses without deleting history") { _ = try fullArchive.add(source: source) }
    try check(try Data(contentsOf: full.appendingPathComponent(CaptureArchive.indexFileName)) == fullIndex, "Archive limit preserves index")
    try check(try files(full) == [CaptureArchive.indexFileName], "Archive limit creates no stray files")
    let summary: [String: Any] = ["checks": checks, "recordsInArchive": archive.records.count, "sourcePreserved": true, "thumbnailMaximum": 600, "maximumRecords": CaptureArchive.maximumRecords]
    try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("validation.json"))
    print("BakerCaptureRegression: \(checks) checks passed")
}

do { try run() } catch { fputs("BakerCaptureRegression failed: \(error)\n", stderr); exit(1) }
