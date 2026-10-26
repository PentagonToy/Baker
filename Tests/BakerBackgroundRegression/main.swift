import AppKit
import ImageIO

func image(_ url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw BakerError(message: "Fixture cannot be read", code: .invalidInput) }
    return cg
}
func bytes(_ image: CGImage) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    data.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return data
}
func write(_ image: CGImage, _ url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil); precondition(CGImageDestinationFinalize(destination))
}
var checks = 0, metrics: [[String: Any]] = []
func check(_ condition: Bool, _ message: String) { precondition(condition, message); checks += 1 }
let out = URL(fileURLWithPath: CommandLine.arguments[1])
for name in ["light", "dark", "filled", "noise"] {
    let source = try image(out.appendingPathComponent(name + ".png")), before = bytes(source)
    let truth = bytes(try image(out.appendingPathComponent(name + "-foreground.png")))
    let start = ProcessInfo.processInfo.systemUptime
    let result = try ImageBackgroundRemoval.remove(source, mode: .paper), actual = bytes(result)
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    let foreground = stride(from: 0, to: truth.count, by: 4).filter { truth[$0 + 3] == 255 }
    let background = stride(from: 0, to: truth.count, by: 4).filter { truth[$0 + 3] == 0 }
    let faint = stride(from: 0, to: truth.count, by: 4).filter { truth[$0 + 3] == 51 }
    check(faint.allSatisfy { abs(Int(actual[$0 + 3]) - 51) <= 8 }, "Faint one-pixel lines retained: " + name)
    let lost = foreground.filter { actual[$0 + 3] < 240 }.count
    let residue = background.map { Int(actual[$0 + 3]) }.max()!
    check(lost == 0, "Opaque text, axes, dots and filled figures retained: " + name)
    check(residue <= 8, "Background is transparent without visible grid seams: " + name)
    check(bytes(source) == before, "Input remains unchanged: " + name)
    check(result.width == source.width && result.height == source.height, "Geometry retained: " + name)
    write(result, out.appendingPathComponent(name + "-removed.png"))
    metrics.append(["fixture": name, "seconds": elapsed, "foreground_pixels": foreground.count, "foreground_pixels_below_alpha240": lost, "background_max_alpha": residue])
}
if CommandLine.arguments.count > 2 {
    let source = try image(URL(fileURLWithPath: CommandLine.arguments[2])), before = bytes(source)
    let start = ProcessInfo.processInfo.systemUptime
    let result = try ImageBackgroundRemoval.remove(source, mode: .paper), after = bytes(result)
    let dark = stride(from: 0, to: before.count, by: 4).filter { max(before[$0], before[$0 + 1], before[$0 + 2]) <= 10 }
    check(dark.allSatisfy { after[$0 + 3] >= 240 }, "Private sample black stroke cores preserved")
    check(bytes(source) == before, "Private sample unchanged")
    write(result, out.appendingPathComponent("sample-removed.png"))
    metrics.append(["fixture": "private-sample", "seconds": ProcessInfo.processInfo.systemUptime - start, "black_core_pixels": dark.count, "black_core_min_alpha": dark.map { Int(after[$0 + 3]) }.min() ?? 0])
}
try JSONSerialization.data(withJSONObject: ["checks": checks, "metrics": metrics], options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("metrics.json"))
print("Passed \(checks) smooth-background checks")
