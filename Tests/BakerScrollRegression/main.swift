import AppKit
import BakerCore
import CoreText
import ImageIO
import CoreVideo
import VideoToolbox

var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
    guard try condition() else { throw BakerError(message: "FAIL: \(name)", code: .operationFailed) }
    checks += 1; print("PASS \(name)")
}
func page(repeating: Bool = false, blankMargin: Int = 36) -> CGImage {
    let width = 640, height = 2600
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateWithName("Helvetica" as CFString, 15, nil)
    for row in 0..<80 {
        let identifier = repeating ? 0 : row
        let top = 28 + row * 31
        if row % 8 == 0 || repeating {
            context.setFillColor(CGColor(gray: repeating ? 0.90 : CGFloat(0.80 + Double(row % 7) * 0.02), alpha: 1))
            context.fill(CGRect(x: blankMargin, y: height - top - 23, width: width - blankMargin * 2, height: 26))
        }
        let text = "Line \(identifier): A native capture preserves every equation and paragraph."
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.1, alpha: 1)]))
        context.textPosition = CGPoint(x: blankMargin + 8, y: height - top - 16)
        CTLineDraw(line, context)
    }
    return context.makeImage()!
}
func crop(_ source: CGImage, _ offset: Int, height: Int = 480) -> CGImage {
    source.cropping(to: CGRect(x: 0, y: offset, width: source.width, height: height))!
}
func rejected(_ outcome: StitchOutcome) -> Bool { if case .rejected = outcome { return true }; return false }
func samePixels(_ left: CGImage, _ right: CGImage) -> Bool {
    guard left.width == right.width, left.height == right.height else { return false }
    func raster(_ image: CGImage) -> CGContext {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context
    }
    let a = raster(left), b = raster(right)
    return memcmp(a.data!, b.data!, left.width * left.height * 4) == 0
}
func write(_ image: CGImage, _ url: URL) throws {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw BakerError(message: "PNG output failed", code: .operationFailed) }
}
guard CommandLine.arguments.count == 2 else { fatalError("Pass an output directory") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
do {
    let source = page()
    var stitcher = ScrollStitcher()
    try check(try stitcher.append(crop(source, 0)) == .started, "first real text-page frame starts immediately")
    for offset in [120, 240, 360, 480] {
        let result = try stitcher.append(crop(source, offset))
        try check(result == .appended(120), "text and blank margins align at \(offset): \(result)")
    }
    let stitched = try stitcher.render()
    try check(stitched.height == 960, "canvas height equals unique captured rows")
    try check(samePixels(stitched, crop(source, 0, height: 960)), "all assembled rows exactly match the original tall page")
    try check(try rejected(stitcher.append(crop(source, 360))), "upward scrolling is rejected without modifying the canvas")
    try check(try rejected(stitcher.append(crop(source, 1600))), "a skipped screen is rejected")
    try check(stitcher.height == 960 && stitcher.acceptedFrames == 5, "rejected frames preserve all accepted rows")
    try check(try stitcher.append(crop(source, 600)) == .appended(120), "matching resumes after returning to the last accepted position")
    var moving = ScrollCaptureBuffer()
    try check(try moving.observe(crop(source, 0)) == .started, "sampling accepts the first frame without a second screenshot")
    for offset in [60, 120, 180] {
        try check(try moving.observe(crop(source, offset)) == nil, "moving frame at \(offset) waits for stable content")
    }
    try check(try moving.observe(crop(source, 180)) == .appended(180), "two stable samples append the final scroll position")
    let finished = try moving.finish()
    try check(finished?.height == 660 && moving.state == .finished, "Finish produces exactly the accepted content")
    do { _ = try moving.finish(); throw BakerError(message: "Finish completed twice", code: .operationFailed) }
    catch { try check(error.localizedDescription != "Finish completed twice", "a second Finish cannot produce another completion") }
    var continuous = ScrollCaptureBuffer()
    _ = try continuous.observe(crop(source, 0), allowMoving: true)
    var continuousCorrect = true
    for offset in stride(from: 20, through: 240, by: 20) {
        if try continuous.observe(crop(source, offset), allowMoving: true) != .appended(20) { continuousCorrect = false }
    }
    try check(continuousCorrect && continuous.acceptedFrames == 13, "continuous moving frames append without a pause or duplicate sample")
    let continuousImage = try continuous.finish()!
    try check(samePixels(continuousImage, crop(source, 0, height: 720)), "continuous capture preserves every original page row")
    var idle = ScrollCaptureBuffer()
    _ = try idle.observe(crop(source, 0))
    try check(try idle.observe(crop(source, 140), settled: true) == .appended(140), "idle stream can settle a final frame without a duplicate capture")
    idle.cancel()
    try check(idle.state == .cancelled && idle.acceptedFrames == 0, "Cancel releases accepted strips")
    try check(try idle.finish() == nil, "Cancel followed by Finish never produces an image")
    do { _ = try idle.append(crop(source, 0)); throw BakerError(message: "Cancelled session accepted frame", code: .operationFailed) }
    catch { try check(error.localizedDescription != "Cancelled session accepted frame", "cancelled sessions cannot accept more content") }
    var one = ScrollCaptureBuffer()
    _ = try one.observe(crop(source, 0))
    try check(try one.finish()?.height == 480, "Finish immediately after the first frame succeeds")
    var repeating = ScrollStitcher()
    let repeatedPage = page(repeating: true)
    _ = try repeating.append(crop(repeatedPage, 0))
    let repeatResult = try repeating.append(crop(repeatedPage, 100))
    try check(rejected(repeatResult), "periodic content is rejected rather than duplicated: \(repeatResult)")
    var many = ScrollCaptureBuffer()
    _ = try many.observe(try ScrollStitcher.ownedCopy(crop(source, 0)))
    var allOffsetsCorrect = true
    // Each sample owns a separate raster, as a live frame would. Do not keep a frame array.
    for offset in stride(from: 20, through: 2000, by: 20) {
        let outcome = try autoreleasepool { try many.observe(ScrollStitcher.ownedCopy(crop(source, offset)), settled: true) }
        if outcome != .appended(20) { allOffsetsCorrect = false; break }
    }
    try check(allOffsetsCorrect && many.acceptedFrames == 101 && many.height == 2480, "one hundred separate scrolling frames retain only their unique rows")
    let longResult = try many.finish()!
    try check(samePixels(longResult, crop(source, 0, height: 2480)), "one hundred small shifts reconstruct the complete page exactly")
    try write(source, directory.appendingPathComponent("text-page.png"))
    try write(stitched, directory.appendingPathComponent("stitched-text-page.png"))
    try write(finished!, directory.appendingPathComponent("settled-moving-page.png"))
    try write(longResult, directory.appendingPathComponent("hundred-frame-page.png"))
    // ScreenCaptureKit reuses pixel buffers. Accepted strips must own their pixels
    // even when the sampler borrows the current VideoToolbox image without copying.
    var surface: CVPixelBuffer?
    try check(CVPixelBufferCreate(kCFAllocatorDefault, 640, 480, kCVPixelFormatType_32BGRA,
        [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &surface) == kCVReturnSuccess,
        "shared capture surface allocates")
    let shared = surface!
    CVPixelBufferLockBaseAddress(shared, [])
    let base = CVPixelBufferGetBaseAddress(shared)!
    let stride = CVPixelBufferGetBytesPerRow(shared)
    let raster = CGContext(data: base, width: 640, height: 480, bitsPerComponent: 8, bytesPerRow: stride,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    raster.draw(crop(source, 0), in: CGRect(x: 0, y: 0, width: 640, height: 480))
    CVPixelBufferUnlockBaseAddress(shared, [])
    var borrowed: CGImage?
    try check(VTCreateCGImageFromCVPixelBuffer(shared, options: nil, imageOut: &borrowed) == noErr, "shared surface produces a borrowed frame")
    var ownership = ScrollCaptureBuffer()
    _ = try ownership.observe(borrowed!, allowMoving: true)
    CVPixelBufferLockBaseAddress(shared, [])
    memset(base, 0, stride * 480)
    CVPixelBufferUnlockBaseAddress(shared, [])
    let owned = try ownership.finish()!
    try check(samePixels(owned, crop(source, 0)), "accepted frame survives capture-surface reuse without a sampler copy")
    print("\(checks) scrolling checks passed")
} catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
