import AppKit
import Foundation

/// A small, self-contained SVG subset produced by Baker's tracing engines.
public struct CaptureSVG: Sendable {
    public static let maximumBytes = 8 * 1024 * 1024
    public let data: Data
    public let width: Int
    public let height: Int
    public init(data: Data) throws {
        guard !data.isEmpty, data.count <= Self.maximumBytes, let text = String(data: data, encoding: .utf8),
              !text.uppercased().contains("<!DOCTYPE"), !text.uppercased().contains("<!ENTITY") else {
            throw BakerError(message: "The vector image contains unsupported declarations or exceeds 8 MB.", code: .invalidInput)
        }
        let validator = SVGValidator(), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = validator
        guard parser.parse(), validator.valid, validator.paths > 0, let width = validator.width, let height = validator.height,
              width > 0, height > 0, width <= CaptureArchive.maximumDimension, height <= CaptureArchive.maximumDimension,
              width * height <= CaptureArchive.maximumPixels else {
            throw BakerError(message: "The vector image is not a supported, self-contained SVG.", code: .invalidInput)
        }
        self.data = data; self.width = width; self.height = height
    }
    public func raster(maximumPixelSize: Int) throws -> CGImage {
        guard (1...CaptureArchive.maximumDimension).contains(maximumPixelSize) else { throw BakerError(message: "The vector preview size is invalid.", code: .invalidInput) }
        let scale = min(1, CGFloat(maximumPixelSize) / CGFloat(max(width, height)))
        let w = max(1, Int((CGFloat(width) * scale).rounded())), h = max(1, Int((CGFloat(height) * scale).rounded()))
        guard let image = NSImage(data: data), let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw BakerError(message: "The vector preview could not be prepared.", code: .previewFailed)
        }
        var rect = CGRect(x: 0, y: 0, width: w, height: h)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw BakerError(message: "The vector preview could not be rendered.", code: .previewFailed)
        }
        context.draw(cg, in: rect)
        guard let result = context.makeImage() else { throw BakerError(message: "The vector preview could not be rendered.", code: .previewFailed) }
        return result
    }
}
private final class SVGValidator: NSObject, XMLParserDelegate {
    var valid = true, paths = 0, nodes = 0, depth = 0
    var width: Int?, height: Int?
    private let elements: Set<String> = ["svg", "g", "path", "metadata", "title", "desc", "rect", "circle", "ellipse", "polygon", "polyline", "line"]
    private let attributes: Set<String> = ["xmlns", "version", "width", "height", "viewBox", "preserveAspectRatio", "d", "fill", "fill-rule", "fill-opacity", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin", "stroke-opacity", "opacity", "transform", "x", "y", "x1", "y1", "x2", "y2", "cx", "cy", "r", "rx", "ry", "points", "id"]
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes values: [String: String]) {
        nodes += 1; depth += 1
        if name == "path" { paths += 1 }
        guard elements.contains(name), nodes <= 60_000, paths <= 50_000, depth <= 64,
              nodes != 1 || name == "svg" else { valid = false; parser.abortParsing(); return }
        if nodes == 1 { width = values["width"].flatMap(Int.init); height = values["height"].flatMap(Int.init) }
        for (key, value) in values {
            let lower = value.lowercased()
            guard attributes.contains(key), !lower.contains("url"), !lower.contains("javascript:"), !lower.contains("data:"),
                  key != "xmlns" || value == "http://www.w3.org/2000/svg" else { valid = false; parser.abortParsing(); return }
        }
    }
    func parser(_ parser: XMLParser, didEndElement: String, namespaceURI: String?, qualifiedName: String?) { depth -= 1 }
    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget: String, data: String?) { valid = false; parser.abortParsing() }
}
