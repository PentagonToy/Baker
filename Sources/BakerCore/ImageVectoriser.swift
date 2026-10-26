import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageVectorMode: String, CaseIterable, Sendable { case colour = "Colour", monochrome = "Black & White" }
public struct ImageVectorTools: Sendable {
    public let python: URL
    public let worker: URL
    public let directory: URL
    public init(python: URL, worker: URL, directory: URL) { self.python = python; self.worker = worker; self.directory = directory }
}
public enum ImageVectoriser {
    public static func convert(_ image: CGImage, mode: ImageVectorMode, tools: ImageVectorTools) throws -> Data {
        guard image.width * image.height <= 4_000_000 else {
            throw BakerError(message: "Crop this image to 4 megapixels or less before vectorising.", code: .resourceLimit)
        }
        guard FileManager.default.isExecutableFile(atPath: tools.python.path), FileManager.default.fileExists(atPath: tools.worker.path),
              FileManager.default.fileExists(atPath: tools.directory.appendingPathComponent("python/vtracer").path),
              FileManager.default.isExecutableFile(atPath: tools.directory.appendingPathComponent("bin/potrace").path) else {
            throw BakerError(message: "Vector conversion is unavailable in this app. Install a complete Baker build.", code: .configurationInvalid, recovery: .updateApp)
        }
        try Task.checkCancellation()
        let job = FileManager.default.temporaryDirectory.appendingPathComponent("baker-vector-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: job, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: job) }
        let input = job.appendingPathComponent("edited.png"), output = job.appendingPathComponent("result.svg")
        guard let writer = CGImageDestinationCreateWithURL(input as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw BakerError(message: "The edited image could not be prepared.", code: .exportFailed)
        }
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else { throw BakerError(message: "The edited image could not be encoded.", code: .exportFailed) }
        let result = try runProcess(tools.python, arguments: ["-I", "-B", tools.worker.path, "--input", input.path, "--output", output.path,
            "--tools", tools.directory.path, "--mode", mode == .colour ? "colour" : "monochrome"], timeout: 60, maximumOutputBytes: 64 * 1024)
        guard result.status == 0 else { throw BakerError(message: result.diagnostic ?? "The image could not be vectorised. Try a smaller crop.", code: .exportFailed) }
        try Task.checkCancellation()
        let reader = try FileHandle(forReadingFrom: output); defer { try? reader.close() }
        let data = try reader.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data()
        guard !data.isEmpty, data.count <= 8 * 1024 * 1024 else { throw BakerError(message: "The vector result exceeds the supported size.", code: .resourceLimit) }
        _ = try CaptureSVG(data: data)
        return data
    }
}
