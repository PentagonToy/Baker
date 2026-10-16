import AppKit
import BakerCore
import Foundation
import ImageIO

struct RegressionFailure: Error, CustomStringConvertible { let description: String }
var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw RegressionFailure(description: message) }
    checks += 1
}
func rejects(_ message: String, operation: () throws -> Void) throws {
    do { try operation() } catch { checks += 1; return }
    throw RegressionFailure(description: "Expected rejection: " + message)
}
func fixture(width: Int = 180, height: Int = 120) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.45, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
    return context.makeImage()!
}
func write(_ image: CGImage, to url: URL, type: String = "public.png", count: Int = 1, orientation: Int = 1) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, count, nil) else { throw RegressionFailure(description: "Fixture image destination") }
    for _ in 0..<count { CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary) }
    try check(CGImageDestinationFinalize(destination), "Fixture image encoding")
}
func decode(_ data: Data) throws -> CGImage {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
        throw RegressionFailure(description: "Clipboard image data does not decode")
    }
    return image
}
func colour(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
    var pixel = [UInt8](repeating: 0, count: 4)
    pixel.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
    }
    return pixel
}

func child(_ arguments: [String]) throws -> Data {
    let process = Process(), output = Pipe(), errors = Pipe()
    guard let executable = Bundle.main.executableURL else { throw RegressionFailure(description: "The clipboard regression executable could not be located.") }
    process.executableURL = executable
    process.arguments = arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output; process.standardError = errors
    try process.run(); process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw RegressionFailure(description: "Clipboard child failed: " + String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)) }
    return output.fileHandleForReading.readDataToEndOfFile()
}

func clipboardChildMode() throws -> Bool {
    let arguments = CommandLine.arguments
    guard arguments.count > 1, ["--publish", "--read"].contains(arguments[1]) else { return false }
    guard let name = arguments.last, name.hasPrefix("BakerClipboardRegression-") else { throw RegressionFailure(description: "Child mode requires a private regression pasteboard.") }
    let board = NSPasteboard(name: .init(name))
    if arguments[1] == "--publish", arguments.count == 4 {
        try ImageClipboard.write(imageURL: URL(fileURLWithPath: arguments[2]), to: board)
    } else if arguments[1] == "--read", arguments.count == 3 {
        defer { board.releaseGlobally() }
        let png = try decode(board.data(forType: .png) ?? Data())
        let tiff = try decode(board.data(forType: .tiff) ?? Data())
        let record: [String: Any] = ["pngWidth": png.width, "tiffWidth": tiff.width, "appKitRead": NSImage(pasteboard: board) != nil]
        print(String(decoding: try JSONSerialization.data(withJSONObject: record, options: .sortedKeys), as: UTF8.self))
    } else { throw RegressionFailure(description: "Invalid clipboard child arguments.") }
    return true
}

func run() throws {
    guard CommandLine.arguments.count == 2 else { throw RegressionFailure(description: "Pass a fresh evidence directory outside source.") }
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    guard !FileManager.default.fileExists(atPath: root.path) else { throw RegressionFailure(description: "Evidence directory must be fresh.") }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let pasteboard = NSPasteboard(name: .init("BakerClipboardRegression-" + UUID().uuidString))
    let legacy = NSPasteboard(name: .init("BakerLegacyClipboardRegression-" + UUID().uuidString))
    defer { pasteboard.releaseGlobally(); legacy.releaseGlobally() }
    var summaries: [[String: Any]] = []
    let original = fixture()
    for (type, suffix) in [("public.png", "png"), ("public.jpeg", "jpg"), ("public.tiff", "tiff"), ("public.heic", "heic"), ("com.microsoft.bmp", "bmp")] {
        let source = root.appendingPathComponent("source." + suffix)
        try write(original, to: source, type: type)
        let bytes = try Data(contentsOf: source)
        let payload = try ImageClipboard.prepare(imageURL: source)
        try check(try Data(contentsOf: source) == bytes, "Copy preserves source " + suffix)
        try FileManager.default.removeItem(at: source)
        try ImageClipboard.write(payload, to: pasteboard)
        try check(pasteboard.pasteboardItems?.count == 1, "One clipboard item " + suffix)
        guard let png = pasteboard.data(forType: .png), let tiff = pasteboard.data(forType: .tiff) else { throw RegressionFailure(description: "Missing PNG/TIFF clipboard formats") }
        let pngImage = try decode(png), tiffImage = try decode(tiff)
        try check(pngImage.width == 180 && pngImage.height == 120, "PNG full resolution after source deletion " + suffix)
        try check(tiffImage.width == 180 && tiffImage.height == 120, "TIFF full resolution after source deletion " + suffix)
        try check(colour(pngImage, x: 20, y: 20) == colour(tiffImage, x: 20, y: 20), "Clipboard formats preserve same pixels " + suffix)
        guard let appKit = NSImage(pasteboard: pasteboard), let cg = appKit.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw RegressionFailure(description: "NSImage pasteboard read failed: " + suffix) }
        try check(cg.width == 180 && cg.height == 120, "AppKit clipboard interoperability " + suffix)
        try png.write(to: root.appendingPathComponent("copied-" + suffix + ".png"))
        try tiff.write(to: root.appendingPathComponent("copied-" + suffix + ".tiff"))
        summaries.append(["sourceType": type, "pngBytes": png.count, "tiffBytes": tiff.count, "sourceDeletedBeforeRead": true, "appKitRead": true])
    }
    let rotated = root.appendingPathComponent("rotated.jpg")
    try write(original, to: rotated, type: "public.jpeg", orientation: 6)
    try ImageClipboard.write(imageURL: rotated, to: pasteboard)
    let rotatedPNG = try decode(pasteboard.data(forType: .png)!)
    try check(rotatedPNG.width == 120 && rotatedPNG.height == 180, "EXIF orientation is applied to clipboard pixels")

    pasteboard.clearContents(); try check(pasteboard.setString("keep previous clipboard", forType: .string), "Private pasteboard marker")
    let malformed = root.appendingPathComponent("invalid.png")
    try Data("not an image".utf8).write(to: malformed)
    try rejects("Invalid input") { try ImageClipboard.write(imageURL: malformed, to: pasteboard) }
    try check(pasteboard.string(forType: .string) == "keep previous clipboard", "Read/encode failure preserves existing clipboard")
    let oversized = root.appendingPathComponent("oversized.png")
    try write(fixture(width: 8193, height: 1), to: oversized)
    try rejects("Image dimension limit") { try ImageClipboard.write(imageURL: oversized, to: pasteboard) }
    try check(pasteboard.string(forType: .string) == "keep previous clipboard", "Size rejection preserves existing clipboard")
    let multi = root.appendingPathComponent("multi.tiff")
    try write(fixture(), to: multi, type: "public.tiff", count: 2)
    try rejects("Multipage image") { try ImageClipboard.write(imageURL: multi, to: pasteboard) }
    try rejects("Non-file URL") { try ImageClipboard.write(imageURL: URL(string: "https://invalid.example/image.png")!, to: pasteboard) }

    let processSource = root.appendingPathComponent("process-source.png")
    try write(original, to: processSource)
    let processBoard = "BakerClipboardRegression-" + UUID().uuidString
    _ = try child(["--publish", processSource.path, processBoard])
    try FileManager.default.removeItem(at: processSource)
    let processData = try child(["--read", processBoard])
    let processRead = try JSONSerialization.jsonObject(with: processData) as! [String: Any]
    try check(processRead["pngWidth"] as? Int == 180, "PNG survives writer process exit")
    try check(processRead["tiffWidth"] as? Int == 180, "TIFF survives writer process exit")
    try check(processRead["appKitRead"] as? Bool == true, "AppKit can read after writer process exit")

    let lazySource = root.appendingPathComponent("legacy-source.png")
    try write(original, to: lazySource)
    guard let lazyImage = NSImage(contentsOf: lazySource) else { throw RegressionFailure(description: "Legacy source read") }
    try FileManager.default.removeItem(at: lazySource)
    legacy.clearContents()
    let legacyWrite = legacy.writeObjects([lazyImage])
    let diagnostic: [String: Any] = ["writeReportedSuccess": legacyWrite, "advertisedTypes": legacy.types?.map(\.rawValue) ?? [], "pngAvailable": legacy.data(forType: .png) != nil, "tiffAvailable": legacy.data(forType: .tiff) != nil, "appKitRead": NSImage(pasteboard: legacy) != nil]
    let report: [String: Any] = ["checks": checks, "privatePasteboardsOnly": true, "representations": summaries, "legacyAfterSourceDeletion": diagnostic, "afterWriterProcessExit": processRead]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("validation.json"))
    print("BakerClipboardRegression: \(checks) checks passed; legacy: \(diagnostic)")
}

do { if try !clipboardChildMode() { try run() } } catch { fputs("BakerClipboardRegression failed: \(error)\n", stderr); exit(1) }
