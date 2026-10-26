import CoreGraphics
import Foundation

public enum StitchOutcome: Equatable {
    case started
    case appended(Int)
    case unchanged
    case rejected(String)
}

/// Owns accepted strips until Finish or Cancel, without retaining a frame history.
public struct ScrollCaptureBuffer {
    public enum State { case collecting, finished, cancelled }
    public private(set) var state: State = .collecting
    private var stitcher = ScrollStitcher()
    private var candidate: CGImage?
    public init() {}
    public var acceptedFrames: Int { stitcher.acceptedFrames }
    public var width: Int { stitcher.width }
    public var height: Int { stitcher.height }

    public mutating func append(_ image: CGImage) throws -> StitchOutcome {
        guard state == .collecting else { throw BakerError(message: "This scrolling capture has already ended.", code: .invalidState) }
        return try stitcher.append(image)
    }

    /// Start immediately. Continuous mode validates overlap; stable mode waits for matching samples.
    public mutating func observe(_ image: CGImage, settled: Bool = false, allowMoving: Bool = false) throws -> StitchOutcome? {
        guard state == .collecting else { throw BakerError(message: "This scrolling capture has already ended.", code: .invalidState) }
        defer { candidate = allowMoving ? nil : image }
        if acceptedFrames == 0 { return try append(image) }
        if !settled && !allowMoving {
            guard let candidate, try ScrollStitcher.isStable(candidate, image) else { return nil }
        }
        return try append(image)
    }

    public mutating func finish() throws -> CGImage? {
        if state == .cancelled { return nil }
        guard state == .collecting else { throw BakerError(message: "This scrolling capture has already ended.", code: .invalidState) }
        guard acceptedFrames > 0 else { throw BakerError(message: "No screen frame was captured. Try again after checking Screen Recording permission.", code: .captureFailed) }
        let image = try stitcher.render()
        stitcher = ScrollStitcher(); candidate = nil; state = .finished
        return image
    }

    public mutating func cancel() {
        guard state == .collecting else { return }
        stitcher = ScrollStitcher(); candidate = nil; state = .cancelled
    }
}

/// Matches only downward movement. Ambiguous frames never alter the accepted canvas.
public struct ScrollStitcher {
    public static let pixelLimit = 32_000_000
    public private(set) var width = 0
    public private(set) var height = 0
    public private(set) var acceptedFrames = 0
    private var previous: FrameSignature?
    private var pieces: [CGImage] = []
    public init() {}

    public static func isStable(_ left: CGImage, _ right: CGImage) throws -> Bool {
        guard left.width == right.width, left.height == right.height else { return false }
        return try FrameSignature(left).error(to: FrameSignature(right), shift: 0) < 0.6
    }

    public mutating func append(_ image: CGImage) throws -> StitchOutcome {
        guard image.width >= 80, image.height >= 100,
              image.width <= 8192, image.height <= 8192,
              image.width * image.height <= Self.pixelLimit else {
            throw BakerError(message: "Choose a region at least 80 × 100px, with each side no larger than 8192px.", code: .invalidInput)
        }
        let signature = try FrameSignature(image)
        guard let previous else {
            self.previous = signature; pieces = [try Self.ownedCopy(image)]
            width = image.width; height = image.height; acceptedFrames = 1
            return .started
        }
        guard width == image.width, previous.height == signature.height else {
            return .rejected("The capture size changed. Start a new capture.")
        }
        if previous.error(to: signature, shift: 0) < 0.3 { return .unchanged }
        let minimumOverlap = max(64, signature.height / 4)
        let maximumShift = signature.height - minimumOverlap
        let scores = (1...maximumShift).map { ($0, previous.error(to: signature, shift: $0, ceiling: 10)) }
        guard let best = scores.min(by: { $0.1 < $1.1 }), best.1 < 7 else {
            return .rejected("No overlap found. Return to the previous position and scroll down more slowly.")
        }
        // Distinct nearby shifts are expected; a second distant match indicates repetition.
        let competitor = scores.filter { abs($0.0 - best.0) > 8 }.map(\.1).min() ?? 255
        guard competitor > best.1 + max(0.3, best.1 * 0.4) else {
            return .rejected("Repeated content makes alignment ambiguous. Select a more distinctive region.")
        }
        // A strong upward match means the user returned to an earlier position.
        // Only the existence of a competitive reverse match matters. Stop as soon
        // as it is found, without allocating another array of every shift score.
        for shift in 1...maximumShift {
            if signature.error(to: previous, shift: shift, ceiling: 10) <= best.1 + 0.3 {
                return .rejected("Upward movement or repeated content detected. Continue down from the last accepted position.")
            }
        }
        let nextHeight = height + best.0
        guard width <= Self.pixelLimit / nextHeight else {
            return .rejected("The 32-megapixel limit was reached. Finish and continue in a separate capture.")
        }
        guard let strip = image.cropping(to: CGRect(x: 0, y: image.height - best.0, width: width, height: best.0)) else {
            throw BakerError(message: "Could not create the next image strip.", code: .captureFailed)
        }
        // Cropped CGImages can retain the complete source. Own only the appended rows.
        pieces.append(try Self.ownedCopy(strip)); height = nextHeight; self.previous = signature; acceptedFrames += 1
        return .appended(best.0)
    }

    public func render() throws -> CGImage {
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw BakerError(message: "Not enough memory to assemble the image.", code: .resourceLimit)
        }
        var top = 0
        for image in pieces {
            context.draw(image, in: CGRect(x: 0, y: height - top - image.height, width: width, height: image.height))
            top += image.height
        }
        guard let result = context.makeImage() else { throw BakerError(message: "Image assembly failed.", code: .captureFailed) }
        return result
    }

    public static func ownedCopy(_ image: CGImage) throws -> CGImage {
        guard image.width > 0, image.height > 0, image.width <= 8192, image.height <= pixelLimit / image.width,
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw BakerError(message: "Could not retain the captured image within its memory limit.", code: .resourceLimit)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let copy = context.makeImage() else { throw BakerError(message: "Could not retain the captured image.", code: .captureFailed) }
        return copy
    }
}

private struct FrameSignature {
    let height: Int
    private let columns = 48
    private let pixels: [UInt8]
    private let features: [UInt8]

    init(_ image: CGImage) throws {
        height = image.height
        // Downsample horizontally, but retain every vertical row for pixel-accurate shifts.
        guard let context = CGContext(data: nil, width: columns, height: height, bitsPerComponent: 8,
            bytesPerRow: columns, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else {
            throw BakerError(message: "Could not prepare image matching.", code: .captureFailed)
        }
        context.interpolationQuality = .low
        // Ignore narrow edge bands containing scrollbars and window borders.
        let inset = max(4, image.width / 30)
        guard let crop = image.cropping(to: CGRect(x: inset, y: 0, width: image.width - 2 * inset, height: height)) else {
            throw BakerError(message: "Could not read the matching region.", code: .captureFailed)
        }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: columns, height: height))
        guard let data = context.data else { throw BakerError(message: "Could not read image data.", code: .captureFailed) }
        pixels = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: columns * height))
        var features = [UInt8](repeating: 0, count: columns * height)
        for y in 0..<height {
            for x in 0..<columns {
                let value = Int(pixels[y * columns + x])
                let horizontal = abs(value - Int(pixels[y * columns + (x + 1 < columns ? x + 1 : x - 1)]))
                let vertical = abs(value - Int(pixels[(y + 1 < height ? y + 1 : max(0, y - 1)) * columns + x]))
                features[y * columns + x] = UInt8(max(horizontal, vertical))
            }
        }
        self.features = features
    }

    func error(to other: FrameSignature, shift: Int, ceiling: Double = .infinity) -> Double {
        let overlap = height - shift
        // Test content at many rows. A fixed header/footer inside the selection raises the error.
        let rowStep = max(1, overlap / 80)
        let maximumSamples = ((overlap + rowStep - 1) / rowStep) * ((columns + 1) / 2)
        var sum = 0, count = 0, fallbackSum = 0, fallbackCount = 0
        for y in stride(from: 0, to: overlap, by: rowStep) {
            for x in stride(from: 0, to: columns, by: 2) {
                let left = (y + shift) * columns + x, right = y * columns + x
                let difference = abs(Int(pixels[left]) - Int(other.pixels[right]))
                fallbackSum += difference; fallbackCount += 1
                // Blank margins must not swamp the text and diagram evidence.
                if max(features[left], other.features[right]) >= 5 { sum += difference; count += 1 }
            }
            // Exact lower bound: even all remaining zero-error samples cannot pass.
            if count >= 8, Double(sum) > ceiling * Double(maximumSamples), Double(fallbackSum) > ceiling * Double(maximumSamples) { return 255 }
        }
        return count >= 8 ? Double(sum) / Double(count) : Double(fallbackSum) / Double(max(1, fallbackCount))
    }
}
