import BakerCore
import AVFoundation
import CoreMedia
import ImageIO

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
    print("PASS \(message)")
}

func centreRGB(_ image: CGImage) -> [Int] {
    let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
    let offset = ((image.height / 2) * image.width + image.width / 2) * 4
    return [Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2])]
}

func sample(index: Int, width: Int = 160, height: Int = 120) throws -> CMSampleBuffer {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
        [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
    guard status == kCVReturnSuccess, let buffer else { fatalError("buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let pointer = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * CVPixelBufferGetBytesPerRow(buffer) + x * 4
            pointer[offset] = UInt8((x + index * 10) % 255)
            pointer[offset + 1] = UInt8(y % 255)
            pointer[offset + 2] = UInt8(index * 20 % 255)
            pointer[offset + 3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    var description: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &description)
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 10),
        presentationTimeStamp: CMTime(value: Int64(index + 100), timescale: 10), decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
        formatDescription: description!, sampleTiming: &timing, sampleBufferOut: &sample)
    return sample!
}

guard CommandLine.arguments.count == 2 else { fatalError("Pass a recording regression output directory.") }
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
Task {
    do {
        let scaled = try RecordingFormat.video.dimensions(width: 3840, height: 2160)
        require(scaled.width == 1920 && scaled.height == 1080, "4K region scales to 1920×1080")
        let odd = try RecordingFormat.gif.dimensions(width: 333, height: 251)
        require(odd.width == 332 && odd.height == 250, "odd dimensions rounded down without upscaling")
        do {
            _ = try RecordingFormat.gif.dimensions(width: 0, height: 120)
            fatalError("invalid dimensions accepted")
        } catch { require(true, "invalid dimensions rejected") }
        let movie = root.appendingPathComponent("synthetic.mp4")
        try? FileManager.default.removeItem(at: movie)
        let writer = try RecordingMovieWriter(url: movie, width: 160, height: 120, format: .gif)
        for index in 0..<10 {
            writer.append(try sample(index: index))
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let output = try await writer.finish()
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        require(tracks.count == 1 && audio.isEmpty, "MP4 has one video track and no audio")
        require(duration.seconds >= 0.9 && duration.seconds < 1.5, "timestamps rebased and bounded")
        let gif = root.appendingPathComponent("synthetic.gif")
        let exported = try await RecordingGIFExporter.export(movie: output, to: gif, cancellation: RecordingCancellation())
        let source = CGImageSourceCreateWithURL(exported as CFURL, nil)!
        require((9...15).contains(CGImageSourceGetCount(source)), "GIF frame count follows 10 fps")
        let first = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let last = CGImageSourceCreateImageAtIndex(source, CGImageSourceGetCount(source) - 1, nil)!
        require(first.width == 160 && first.height == 120 && last.width == 160, "GIF first and last frames decode at expected size")
        for frameIndex in [0, CGImageSourceGetCount(source) / 2, CGImageSourceGetCount(source) - 1] {
            let image = CGImageSourceCreateImageAtIndex(source, frameIndex, [kCGImageSourceShouldCache: false] as CFDictionary)!
            let colour = centreRGB(image)
            let sourceIndex = min(9, frameIndex)
            let expected = [sourceIndex * 20 % 255, 60, (80 + sourceIndex * 10) % 255]
            require(zip(colour, expected).allSatisfy { abs($0 - $1) <= 40 }, "GIF frame \(frameIndex) preserves its source colour and palette")
        }
        var gifDuration = 0.0
        for frameIndex in 0..<CGImageSourceGetCount(source) {
            let metadata = CGImageSourceCopyPropertiesAtIndex(source, frameIndex, nil) as! [CFString: Any]
            let frameProperties = metadata[kCGImagePropertyGIFDictionary] as! [CFString: Any]
            gifDuration += (frameProperties[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (frameProperties[kCGImagePropertyGIFDelayTime] as? Double) ?? 0
        }
        require(abs(gifDuration - duration.seconds) < 0.05, "GIF delays preserve movie duration within 50ms")
        let properties = CGImageSourceCopyProperties(source, nil) as! [CFString: Any]
        let gifProperties = properties[kCGImagePropertyGIFDictionary] as! [CFString: Any]
        require(gifProperties[kCGImagePropertyGIFLoopCount] as? Int == 0, "GIF loops indefinitely")
        let token = RecordingCancellation(); token.cancel()
        let cancelledGIF = root.appendingPathComponent("cancelled.gif")
        do {
            _ = try await RecordingGIFExporter.export(movie: output, to: cancelledGIF, cancellation: token)
            fatalError("cancel did not throw")
        } catch is CancellationError {
            require(!FileManager.default.fileExists(atPath: cancelledGIF.path), "cancelled GIF partial output removed")
        }
        let emptyURL = root.appendingPathComponent("empty.mp4")
        try? FileManager.default.removeItem(at: emptyURL)
        let empty = try RecordingMovieWriter(url: emptyURL, width: 160, height: 120, format: .video)
        do { _ = try await empty.finish(); fatalError("empty did not throw") }
        catch { empty.cancel(); require(true, "empty recording fails explicitly") }
        let cancelURL = root.appendingPathComponent("cancelled.mp4")
        try? FileManager.default.removeItem(at: cancelURL)
        let cancelled = try RecordingMovieWriter(url: cancelURL, width: 160, height: 120, format: .video)
        cancelled.append(try sample(index: 0)); cancelled.cancel()
        do { _ = try await cancelled.finish(); fatalError("cancel did not throw") }
        catch is CancellationError { require(true, "cancelled movie cannot finish successfully") }
        let staticURL = root.appendingPathComponent("static.mp4")
        try? FileManager.default.removeItem(at: staticURL)
        let still = try RecordingMovieWriter(url: staticURL, width: 160, height: 120, format: .video)
        still.append(try sample(index: 0))
        try await Task.sleep(nanoseconds: 350_000_000)
        _ = try await still.finish()
        let staticDuration = try await AVURLAsset(url: staticURL).load(.duration)
        require(staticDuration.seconds >= 0.3 && staticDuration.seconds < 1, "static ending preserves elapsed recording time")
        try? FileManager.default.removeItem(at: emptyURL)
        try? FileManager.default.removeItem(at: cancelURL)
        print("Recording regression passed")
        exit(0)
    } catch { print("FAIL \(error)"); exit(1) }
}
dispatchMain()
