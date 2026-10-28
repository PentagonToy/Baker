import AppKit
import BakerCore
import WebKit

/// One offline WebKit surface, serial requests and a bounded image cache.
/// The workspace displays snapshots, so WebKit is never embedded in each history row.
@MainActor
final class FormulaPreviewRenderer: NSObject, WKNavigationDelegate {
    static let shared = FormulaPreviewRenderer()
    private struct Request {
        let id: UUID
        let source: String
        let continuation: CheckedContinuation<NSImage, Error>
    }
    private let resourceURL: URL?
    private let cache = NSCache<NSString, NSImage>()
    private var webView: WKWebView?
    private var loaded = false
    private var queue: [Request] = []
    private var active: Request?
    private var timeout: Task<Void, Never>?
    private var idleRelease: Task<Void, Never>?
    var resourceState: [String: Any] {
        ["webViewRetained": webView != nil, "rendering": active != nil, "queuedRequests": queue.count,
         "cacheEntryLimit": 12, "cacheCostLimitBytes": 16 * 1024 * 1024]
    }

    init(resourceURL: URL? = nil) {
        #if SWIFT_PACKAGE
        let bundle = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        self.resourceURL = resourceURL ?? bundle.url(forResource: "FormulaPreview", withExtension: nil)
        super.init()
        cache.countLimit = 12
        cache.totalCostLimit = 16 * 1024 * 1024
    }

    func render(_ latex: String) async throws -> NSImage {
        try Task.checkCancellation()
        guard latex.count <= 8000, latex.utf8.count <= 32_000 else {
            throw BakerError(message: "Formula preview is limited to 8,000 characters. The LaTeX is still available.", code: .resourceLimit)
        }
        let source = LatexWhitespace.compact(LatexWhitespace.mathBody(latex))
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BakerError(message: "There is no formula to preview.", code: .invalidInput)
        }
        if let image = cache.object(forKey: source as NSString) { return image }
        guard queue.count < 16 else {
            throw BakerError(message: "Too many formula previews are waiting. Try again shortly.", code: .resourceLimit)
        }
        let id = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                queue.append(Request(id: id, source: source, continuation: continuation))
                startNext()
            }
        }, onCancel: { Task { @MainActor in self.cancel(id) } })
    }

    func clearCache() {
        cache.removeAllObjects()
        timeout?.cancel(); timeout = nil
        idleRelease?.cancel(); idleRelease = nil
        let requests = (active.map { [$0] } ?? []) + queue
        active = nil; queue = []
        resetWebView()
        requests.forEach { $0.continuation.resume(throwing: CancellationError()) }
    }

    private func startNext() {
        guard active == nil, !queue.isEmpty else { return }
        idleRelease?.cancel(); idleRelease = nil
        let request = queue.removeFirst()
        active = request
        timeout = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
            guard let self, self.active?.id == request.id else { return }
            self.resetWebView()
            self.finish(request.id, .failure(BakerError(message: "Formula preview timed out. The LaTeX is still available.", code: .processTimedOut)))
        }
        if loaded { typeset(request); return }
        guard let resourceURL else {
            finish(request.id, .failure(BakerError(message: "The bundled formula renderer is missing.", code: .modelNotReady, recovery: .updateApp))); return
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 4096, height: 2048), configuration: configuration)
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        webView = view
        view.loadFileURL(resourceURL.appendingPathComponent("index.html"), allowingReadAccessTo: resourceURL)
    }

    private func typeset(_ request: Request) {
        guard let view = webView else { return }
        // Arguments cross WebKit's structured bridge, never HTML or script interpolation.
        view.callAsyncJavaScript("return await window.bakerPreview(source);", arguments: ["source": request.source], in: nil, in: .page) { [weak self] result in
            guard let self, self.active?.id == request.id else { return }
            switch result {
            case .failure(let error):
                let detail = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
                self.finish(request.id, .failure(BakerError(message: "Cannot preview this notation: \(String(detail.prefix(400))) The LaTeX is still available.", code: .previewUnsupported)))
            case .success(let value):
                guard let size = value as? [String: NSNumber], let width = size["width"]?.doubleValue,
                      let height = size["height"]?.doubleValue, width.isFinite, height.isFinite,
                      width > 0, height > 0, width <= 4096, height <= 2048, width * height <= 4_000_000 else {
                    self.finish(request.id, .failure(BakerError(message: "Formula preview exceeds its image size limit.", code: .resourceLimit))); return
                }
                let config = WKSnapshotConfiguration()
                config.rect = NSRect(x: 0, y: 0, width: width, height: height)
                config.snapshotWidth = NSNumber(value: width * 2)
                view.takeSnapshot(with: config) { [weak self] image, error in
                    guard let self, self.active?.id == request.id else { return }
                    if let image {
                        do {
                            let bitmap = try self.normaliseSnapshot(image, width: width, height: height)
                            self.cache.setObject(bitmap, forKey: request.source as NSString, cost: Int(width * height * 16))
                            self.finish(request.id, .success(bitmap))
                        } catch { self.finish(request.id, .failure(error)) }
                    } else {
                        self.finish(request.id, .failure(error ?? BakerError(message: "Could not create the formula preview.", code: .previewFailed)))
                    }
                }
            }
        }
    }

    // WebKit backing scale varies by display. Store exactly two pixels per point.
    private func normaliseSnapshot(_ image: NSImage, width: Double, height: Double) throws -> NSImage {
        let pixelsWide = Int(width * 2), pixelsHigh = Int(height * 2)
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: pixelsWide, height: pixelsHigh, bitsPerComponent: 8,
                bytesPerRow: pixelsWide * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw BakerError(message: "Could not allocate the formula preview.", code: .previewFailed)
        }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        guard let bitmap = context.makeImage() else { throw BakerError(message: "Could not finish the formula preview.", code: .previewFailed) }
        return NSImage(cgImage: bitmap, size: NSSize(width: width, height: height))
    }

    private func finish(_ id: UUID, _ result: Result<NSImage, Error>) {
        guard let request = active, request.id == id else { return }
        timeout?.cancel(); timeout = nil; active = nil
        request.continuation.resume(with: result)
        startNext()
        if active == nil && queue.isEmpty {
            idleRelease = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                guard let self, self.active == nil, self.queue.isEmpty else { return }
                self.resetWebView()
                self.idleRelease = nil
            }
        }
    }

    private func resetWebView() {
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil; loaded = false
    }

    private func cancel(_ id: UUID) {
        if active?.id == id {
            resetWebView()
            finish(id, .failure(CancellationError()))
        } else if let index = queue.firstIndex(where: { $0.id == id }) {
            queue.remove(at: index).continuation.resume(throwing: CancellationError())
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView, let request = active else { return }
        loaded = true; typeset(request)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let allowed = navigationAction.request.url?.standardizedFileURL == resourceURL?.appendingPathComponent("index.html").standardizedFileURL
        decisionHandler(allowed ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(webView, error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(webView, error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { failed(webView, BakerError(message: "The formula renderer stopped. Try opening the result again.", code: .previewFailed)) }
    private func failed(_ view: WKWebView, _ error: Error) {
        guard view === webView, let id = active?.id else { return }
        resetWebView(); finish(id, .failure(error))
    }
}
