import AVFoundation
import CoreMedia
import ImageIO
import UniformTypeIdentifiers

public enum RecordingFormat: String, Sendable {
    case video, gif

    public var fileExtension: String { self == .video ? "mp4" : "gif" }
    public var title: String { self == .video ? "Video" : "GIF" }
    public var maximumDuration: TimeInterval { self == .video ? 180 : 30 }
    public var framesPerSecond: Int { self == .video ? 30 : 10 }
    public var maximumDimension: Int { self == .video ? 1920 : 960 }

    /// H.264 requires even dimensions. Never upscale the selected region.
    public func dimensions(width: Int, height: Int) throws -> (width: Int, height: Int) {
        guard width >= 2, height >= 2 else { throw BakerError(message: "The recording region is too small.", code: .invalidInput) }
        let scale = min(1, Double(maximumDimension) / Double(max(width, height)))
        return (max(2, Int(Double(width) * scale) / 2 * 2), max(2, Int(Double(height) * scale) / 2 * 2))
    }
}

/// Serialises writer access without queuing frames. A busy encoder drops incoming frames.
/// The only retained sample is the latest accepted frame, used to preserve a static ending.
public final class RecordingMovieWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let frameInterval: CMTime
    private let maximumDuration: Double
    private var firstTime: CMTime?
    private var lastTime = CMTime.zero
    private var lastSample: CMSampleBuffer?
    private var startedAt: TimeInterval?
    private var closing = false
    private var cancelled = false
    private var dropped = 0
    private var failure: Error?
    public let url: URL

    public init(url: URL, width: Int, height: Int, format: RecordingFormat, capturesAudio: Bool = false) throws {
        guard width >= 2, height >= 2, width <= format.maximumDimension, height <= format.maximumDimension,
              width.isMultiple(of: 2), height.isMultiple(of: 2) else {
            throw BakerError(message: "The recording dimensions are invalid.", code: .invalidInput)
        }
        self.url = url
        maximumDuration = format.maximumDuration
        frameInterval = CMTime(value: 1, timescale: Int32(format.framesPerSecond))
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let bitrate = min(12_000_000, max(400_000, width * height * (format == .video ? 5 : 3)))
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: format.framesPerSecond,
                AVVideoMaxKeyFrameIntervalKey: format.framesPerSecond * 2,
                AVVideoAllowFrameReorderingKey: false]
        ])
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw BakerError(message: "The video encoder is unavailable.", code: .recordingFailed) }
        writer.add(input)
        if capturesAudio && format == .video {
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000])
            audio.expectsMediaDataInRealTime = true
            guard writer.canAdd(audio) else { throw BakerError(message: "The system-audio encoder is unavailable.", code: .recordingFailed) }
            writer.add(audio); audioInput = audio
        } else { audioInput = nil }
        guard writer.startWriting() else { throw writer.error ?? BakerError(message: "Could not start the video encoder.", code: .recordingFailed) }
    }

    public var droppedFrames: Int { lock.lock(); defer { lock.unlock() }; return dropped }
    public var failureError: Error? { lock.lock(); defer { lock.unlock() }; return failure ?? writer.error }

    public func append(_ sample: CMSampleBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !closing, !cancelled, failure == nil, CMSampleBufferIsValid(sample),
              CMSampleBufferDataIsReady(sample), CMSampleBufferGetImageBuffer(sample) != nil else { return }
        guard input.isReadyForMoreMediaData else {
            if writer.status == .failed { failure = writer.error }
            dropped += 1; return
        }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
        guard timestamp.isNumeric else { return }
        if firstTime == nil {
            firstTime = timestamp
            startedAt = ProcessInfo.processInfo.systemUptime
            writer.startSession(atSourceTime: .zero)
        }
        let relativeTime = CMTimeSubtract(timestamp, firstTime!)
        guard relativeTime.seconds >= 0, relativeTime.seconds < maximumDuration,
              lastSample == nil || CMTimeCompare(relativeTime, lastTime) > 0 else { return }
        do {
            let copy = try retimed(sample, at: relativeTime)
            guard input.append(copy) else {
                failure = writer.error ?? BakerError(message: "The video encoder could not accept a frame.", code: .recordingFailed)
                return
            }
            lastSample = copy; lastTime = relativeTime
        } catch { failure = error }
    }

    /// Audio shares the first screen frame's clock. Samples before it are discarded without buffering.
    public func appendAudio(_ sample: CMSampleBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !closing, !cancelled, failure == nil, let audioInput, let firstTime,
              CMSampleBufferIsValid(sample), CMSampleBufferDataIsReady(sample) else { return }
        guard audioInput.isReadyForMoreMediaData else {
            if writer.status == .failed { failure = writer.error }
            return
        }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
        guard timestamp.isNumeric else { return }
        let time = CMTimeSubtract(timestamp, firstTime)
        guard time.seconds >= 0, time.seconds < maximumDuration else { return }
        var count = 0
        guard CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count) == noErr,
              count > 0, count <= 65_536 else { return }
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count) == noErr else { return }
        for index in timing.indices {
            timing[index].presentationTimeStamp = CMTimeSubtract(timing[index].presentationTimeStamp, firstTime)
            if timing[index].decodeTimeStamp.isNumeric { timing[index].decodeTimeStamp = CMTimeSubtract(timing[index].decodeTimeStamp, firstTime) }
        }
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample,
            sampleTimingEntryCount: timing.count, sampleTimingArray: &timing, sampleBufferOut: &copy)
        guard status == noErr, let copy else { failure = BakerError(message: "Could not timestamp system audio.", code: .recordingFailed); return }
        if !audioInput.append(copy) { failure = writer.error ?? BakerError(message: "The audio encoder could not accept a sample.", code: .recordingFailed) }
    }

    public func finish() async throws -> URL {
        try beginFinish()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        let (wasCancelled, status, error) = lock.withLock {
            lastSample = nil
            return (cancelled, writer.status, writer.error)
        }
        if wasCancelled { throw CancellationError() }
        guard status == .completed else { throw error ?? BakerError(message: "Could not finish the recording.", code: .recordingFailed) }
        return url
    }

    private func beginFinish() throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        guard !closing else { throw BakerError(message: "This recording has already ended.", code: .invalidState) }
        closing = true
        if let failure { throw failure }
        guard let lastSample, let startedAt else { throw BakerError(message: "No screen frames were received. Check Screen Recording permission and try again.", code: .captureFailed) }
        let duration = min(maximumDuration, max(lastTime.seconds + frameInterval.seconds,
            ProcessInfo.processInfo.systemUptime - startedAt))
        let ending = CMTime(seconds: duration, preferredTimescale: 600)
        let tail = CMTimeSubtract(ending, frameInterval)
        if CMTimeCompare(tail, lastTime) > 0, input.isReadyForMoreMediaData {
            guard input.append(try retimed(lastSample, at: tail)) else {
                throw writer.error ?? BakerError(message: "Could not finish the last video frame.", code: .recordingFailed)
            }
        }
        writer.endSession(atSourceTime: ending)
        input.markAsFinished()
        audioInput?.markAsFinished()
        self.lastSample = nil
    }

    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return }
        cancelled = true; closing = true; lastSample = nil
        if writer.status == .writing || writer.status == .unknown { writer.cancelWriting() }
    }

    private func retimed(_ sample: CMSampleBuffer, at time: CMTime) throws -> CMSampleBuffer {
        var timing = CMSampleTimingInfo(duration: frameInterval, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy)
        guard status == noErr, let copy else { throw BakerError(message: "Could not timestamp the recording frame (\(status)).", code: .recordingFailed) }
        return copy
    }
}

public final class RecordingCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    public init() {}
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    public func cancel() { lock.lock(); value = true; lock.unlock() }
}

public enum RecordingGIFExporter {
    /// Decodes and releases one frame at a time; GIF duration, dimensions and frame count are bounded.
    public static func export(movie: URL, to output: URL, cancellation: RecordingCancellation) async throws -> URL {
        let asset = AVURLAsset(url: movie)
        let assetDuration = try await asset.load(.duration)
        let duration = min(RecordingFormat.gif.maximumDuration, assetDuration.seconds)
        guard duration.isFinite, duration > 0 else { throw BakerError(message: "The recording has no usable duration.", code: .invalidInput) }
        let fps = RecordingFormat.gif.framesPerSecond
        let frameCount = max(1, min(Int(RecordingFormat.gif.maximumDuration) * fps, Int(ceil(duration * Double(fps)))))
        let destination = try StreamingGIFFile(url: output)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: RecordingFormat.gif.maximumDimension, height: RecordingFormat.gif.maximumDimension)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: Int32(fps))
        generator.requestedTimeToleranceAfter = .zero
        do {
            for index in 0..<frameCount {
                if cancellation.isCancelled { throw CancellationError() }
                let time = CMTime(seconds: Double(index) / Double(fps), preferredTimescale: 600)
                let frame = try await generator.image(at: time)
                let delay = min(1 / Double(fps), duration - Double(index) / Double(fps))
                try autoreleasepool { try destination.append(frame.image, delay: delay) }
            }
            if cancellation.isCancelled { throw CancellationError() }
            try destination.finish()
            return output
        } catch {
            generator.cancelAllCGImageGeneration()
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}

/// ImageIO's animated destination retains frames until finalisation. Encode one still GIF
/// at a time instead, then stream its palette and LZW sub-blocks into a GIF89a animation.
/// Local colour tables let each frame use its own palette without retaining earlier images.
private final class StreamingGIFFile {
    private let file: FileHandle
    private var size: CGSize?
    private var closed = false

    init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw BakerError(message: "Could not create the GIF file.", code: .recordingFailed)
        }
        file = try FileHandle(forWritingTo: url)
    }

    deinit { if !closed { try? file.close() } }

    func append(_ image: CGImage, delay: Double) throws {
        guard image.width > 0, image.height > 0, image.width <= 960, image.height <= 960 else { throw malformed() }
        if size == nil {
            size = CGSize(width: image.width, height: image.height)
            var header = Data("GIF89a".utf8)
            header.append(contentsOf: [UInt8(image.width & 255), UInt8(image.width >> 8),
                UInt8(image.height & 255), UInt8(image.height >> 8), 0x70, 0, 0])
            // Infinite looping application extension; each image gets a local colour table.
            header.append(contentsOf: [0x21, 0xFF, 0x0B])
            header.append(contentsOf: "NETSCAPE2.0".utf8)
            header.append(contentsOf: [3, 1, 0, 0, 0])
            try file.write(contentsOf: header)
        }
        guard size == CGSize(width: image.width, height: image.height) else { throw malformed() }
        let storage = CFDataCreateMutable(kCFAllocatorDefault, 0)!
        guard let encoder = CGImageDestinationCreateWithData(storage, UTType.gif.identifier as CFString, 1, nil) else { throw malformed() }
        CGImageDestinationAddImage(encoder, image, nil)
        guard CGImageDestinationFinalize(encoder) else { throw malformed() }
        let bytes = storage as Data
        guard bytes.count >= 14, bytes.count <= 16 * 1024 * 1024,
              bytes.prefix(6) == Data("GIF87a".utf8) || bytes.prefix(6) == Data("GIF89a".utf8),
              word(bytes, 6) == image.width, word(bytes, 8) == image.height else { throw malformed() }
        let globalBits = bytes[10] & 7
        let globalSize = bytes[10] & 0x80 == 0 ? 0 : 3 * (1 << (Int(globalBits) + 1))
        guard 13 + globalSize < bytes.count else { throw malformed() }
        var cursor = 13 + globalSize
        while cursor < bytes.count, bytes[cursor] == 0x21 {
            guard cursor + 2 < bytes.count else { throw malformed() }
            switch bytes[cursor + 1] {
            case 0xF9:
                // Screen-video frames are opaque. Do not silently discard transparency semantics.
                guard cursor + 7 < bytes.count, bytes[cursor + 2] == 4,
                      bytes[cursor + 3] & 1 == 0, bytes[cursor + 7] == 0 else { throw malformed() }
            case 0xFF, 0xFE: break // Single-frame application metadata and comments have no image semantics.
            default: throw malformed()
            }
            cursor += 2
            try skipSubBlocks(bytes, cursor: &cursor)
        }
        guard cursor + 10 < bytes.count, bytes[cursor] == 0x2C else { throw malformed() }
        var descriptor = bytes.subdata(in: cursor..<(cursor + 10))
        let packed = descriptor[9]
        guard word(descriptor, 1) == 0, word(descriptor, 3) == 0,
              word(descriptor, 5) == image.width, word(descriptor, 7) == image.height,
              packed & 0x18 == 0 else { throw malformed() }
        cursor += 10
        let palette: Data
        if packed & 0x80 != 0 {
            let length = 3 * (1 << (Int(packed & 7) + 1))
            guard cursor + length < bytes.count else { throw malformed() }
            palette = bytes.subdata(in: cursor..<(cursor + length)); cursor += length
        } else {
            guard globalSize > 0 else { throw malformed() }
            palette = bytes.subdata(in: 13..<(13 + globalSize))
            descriptor[9] = (packed & 0x40) | 0x80 | globalBits
        }
        let imageDataStart = cursor
        guard cursor < bytes.count, (2...8).contains(bytes[cursor]) else { throw malformed() }
        cursor += 1 // LZW minimum code size precedes the image data sub-blocks.
        try skipSubBlocks(bytes, cursor: &cursor)
        guard cursor + 1 == bytes.count, bytes[cursor] == 0x3B else { throw malformed() }
        let centiseconds = max(1, min(65535, Int((delay * 100).rounded())))
        try file.write(contentsOf: Data([0x21, 0xF9, 4, 4, UInt8(centiseconds & 255), UInt8(centiseconds >> 8), 0, 0]))
        try file.write(contentsOf: descriptor)
        try file.write(contentsOf: palette)
        try file.write(contentsOf: bytes.subdata(in: imageDataStart..<cursor))
    }

    func finish() throws {
        guard size != nil, !closed else { throw malformed() }
        try file.write(contentsOf: Data([0x3B]))
        try file.close(); closed = true
    }

    private func skipSubBlocks(_ bytes: Data, cursor: inout Int) throws {
        while cursor < bytes.count {
            let length = Int(bytes[cursor]); cursor += 1
            if length == 0 { return }
            guard length <= bytes.count - cursor else { throw malformed() }
            cursor += length
        }
        throw malformed()
    }

    private func malformed() -> BakerError { BakerError(message: "Could not encode a GIF frame.", code: .recordingFailed) }
    private func word(_ bytes: Data, _ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
}
