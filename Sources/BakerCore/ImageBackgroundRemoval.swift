import CoreGraphics
import CoreImage
import Foundation
import Vision

public enum BackgroundRemovalMode: Sendable { case paper, subject }

/// Short-lived operations; original pixels and dimensions are retained by the editor for Undo.
public enum ImageBackgroundRemoval {
    public static let maximumPixels = 8_000_000
    public static func remove(_ image: CGImage, mode: BackgroundRemovalMode) throws -> CGImage {
        guard image.width * image.height <= maximumPixels else {
            throw BakerError(message: "Crop this image to 8 megapixels or less before removing its background.", code: .resourceLimit)
        }
        try Task.checkCancellation()
        switch mode {
        case .paper: return try removePaper(image)
        case .subject:
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request]); try Task.checkCancellation()
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
                throw BakerError(message: "No clear subject was found. Try Paper & Slides for a diagram.", code: .recognitionFailed)
            }
            let mask = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
            let source = CIImage(cgImage: image)
            let result = source.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: source.extent),
                kCIInputMaskImageKey: CIImage(cvPixelBuffer: mask)
            ])
            let context = CIContext(options: [.cacheIntermediates: false])
            guard let output = context.createCGImage(result, from: source.extent) else {
                throw BakerError(message: "The cutout could not be rendered.", code: .previewFailed)
            }
            try Task.checkCancellation(); return output
        }
    }
    private static func removePaper(_ image: CGImage) throws -> CGImage {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                throw BakerError(message: "The background could not be prepared.", code: .exportFailed)
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let paper = try PaperBackground(pixels: pixels, width: w, height: h)
        var changed = false, foreground = false
        var colour = [Float](repeating: 0, count: 3)
        for y in 0..<h {
            if y.isMultiple(of: 32) { try Task.checkCancellation() }
            for x in 0..<w {
                let i = (y * w + x) * 4, oldAlpha = Float(pixels[i + 3]) / 255
                guard oldAlpha > 0 else { pixels[i] = 0; pixels[i + 1] = 0; pixels[i + 2] = 0; continue }
                let estimated = paper.colour(x: x, y: y)
                let background = SIMD3<Float>(Float(estimated.x), Float(estimated.y), Float(estimated.z))
                var alpha: Float = 0, difference: Float = 0
                for c in 0..<3 {
                    colour[c] = min(1, Float(pixels[i + c]) / 255 / oldAlpha)
                    let delta = colour[c] - background[c]
                    difference = max(difference, abs(delta) * 255)
                    if paper.adaptive && abs(delta) * 255 <= 6 { continue }
                    alpha = max(alpha, delta < 0 ? -delta / max(background[c], 0.000001) : delta / max(1 - background[c], 0.000001))
                }
                alpha = min(1, max(0, alpha))
                if paper.adaptive {
                    let confidence = min(1, max(0, (difference - 6) / 8))
                    alpha *= confidence * confidence * (3 - 2 * confidence)
                }
                let newAlpha = alpha * oldAlpha
                changed = changed || newAlpha < oldAlpha - 0.01; foreground = foreground || newAlpha > 0.01
                for c in 0..<3 {
                    let value = alpha > 0.000001 ? min(1, max(0, background[c] + (colour[c] - background[c]) / alpha)) : 0
                    pixels[i + c] = UInt8((value * newAlpha * 255).rounded())
                }
                pixels[i + 3] = UInt8((newAlpha * 255).rounded())
            }
        }
        guard changed, foreground else { throw BakerError(message: "No distinct paper background and foreground were found. The image has not changed.", code: .invalidInput) }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let output = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw BakerError(message: "The transparent image could not be rendered.", code: .exportFailed) }
        return output
    }
}
