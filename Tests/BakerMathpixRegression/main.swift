import Foundation
import CoreGraphics
import BakerCore

final class MathpixProtocol: URLProtocol, @unchecked Sendable {
    static var replies: [(Int, Data)] = []
    static var failure: URLError?
    static var requests = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        if let error = Self.failure { client?.urlProtocol(self, didFailWithError: error); return }
        guard !Self.replies.isEmpty else { fatalError("Unexpected remote retry") }
        let (status, data) = Self.replies.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct MathpixRegression {
    static func client(_ replies: [(Int, String)] = [], failure: URLError? = nil) -> MathpixClient {
        MathpixProtocol.replies = replies.map { ($0.0, Data($0.1.utf8)) }; MathpixProtocol.failure = failure; MathpixProtocol.requests = 0
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MathpixProtocol.self]
        return MathpixClient(network: URLSession(configuration: config), session: .init(email: "synthetic@example.invalid", token: "synthetic-test-token"))
    }
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let image = root.appendingPathComponent("image.png"); try Data([1,2,3]).write(to: image)
        let good = client([(201, #"{"text_display":"\\[x^{2}+3x-4=0\\]"}"#)])
        let result = try await good.recognise(image)
        precondition(result.latex == "x^{2}+3x-4=0" && result.model == "Mathpix · Online" && result.confidence == nil)
        let expired = client([(401, "{}")])
        do { _ = try await expired.recognise(image); fatalError("Expired session accepted") }
        catch MathpixClient.Failure.expired {}
        do { _ = try await expired.recognise(image); fatalError("Expired session retried") }
        catch MathpixClient.Failure.expired {}
        precondition(MathpixProtocol.requests == 1)
        let quota = client([(400, #"{"errors":[{"id":"snip_max_limit"}]}"#)])
        do { _ = try await quota.recognise(image); fatalError("Quota failure hidden") }
        catch MathpixClient.Failure.quota {}
        precondition(MathpixProtocol.requests == 1)
        let offline = client(failure: URLError(.notConnectedToInternet))
        do { _ = try await offline.recognise(image); fatalError("Offline success") }
        catch let error as URLError { precondition(error.code == .notConnectedToInternet) }
        let cancelled = client(failure: URLError(.cancelled))
        do { _ = try await cancelled.recognise(image); fatalError("Cancellation hidden") }
        catch is CancellationError {}
        let empty = client([(201, #"{"text_display":" "}"#)])
        do { _ = try await empty.recognise(image); fatalError("Empty result accepted") }
        catch MathpixClient.Failure.invalidResponse {}
        let pdf = root.appendingPathComponent("source.pdf")
        var bounds = CGRect(x: 0, y: 0, width: 300, height: 300)
        let consumer = CGDataConsumer(url: pdf as CFURL)!, context = CGContext(consumer: consumer, mediaBox: &bounds, nil)!
        context.beginPDFPage(nil); context.endPDFPage(); context.closePDF()
        let output = root.appendingPathComponent("document.md")
        let document = client([(200, #"{"pdf":{"id":"synthetic-pdf"}}"#), (200, #"{"pdf":{"status":"completed"}}"#), (200, "# Synthetic\n\nEquation")])
        let report = try await document.convert(source: pdf, destination: output, format: .markdown) { _,_,_ in }
        precondition(report.totalPages == 1 && report.destination == output && FileManager.default.fileExists(atPath: output.path))
        do { _ = try await document.convert(source: pdf, destination: output, format: .markdown) { _,_,_ in }; fatalError("Output overwritten") }
        catch let error as BakerError { precondition(error.code == .storageConflict) }
        precondition(MathpixProtocol.requests == 3)
        let latex = client([(200, #"{"pdf":{"id":"synthetic-pdf"}}"#), (200, #"{"pdf":{"status":"completed"}}"#), (200, "PKsynthetic")])
        let tex = root.appendingPathComponent("document.tex")
        let archive = try await latex.convert(source: pdf, destination: tex, format: .latex) { _,_,_ in }
        precondition(archive.destination.pathExtension == "zip" && !FileManager.default.fileExists(atPath: tex.path))
        print("Passed Mathpix formula, expiry/no-retry, quota, offline, cancellation, empty result, PDF, overwrite and LaTeX archive checks")
    }
}
