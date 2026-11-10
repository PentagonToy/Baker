import WebKit

struct WebImportDocument: Sendable {
    let title: String
    let printText: String
}

@MainActor
final class WebImportRenderer: NSObject, WKNavigationDelegate {
    private let directory: URL?
    private var view: WKWebView?
    private var continuation: CheckedContinuation<WebImportDocument, Error>?
    private var timeout: Task<Void, Never>?

    init(directory: URL? = nil) {
        #if SWIFT_PACKAGE
        let bundle = Bundle.main.bundleURL.pathExtension == "app" ? Bundle.main : Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        self.directory = directory ?? bundle.url(forResource: "WebImport", withExtension: nil)
    }

    func convert(_ source: WebImportSource) async throws -> WebImportDocument {
        let page = try await source.read()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard let directory, continuation == nil else { throw WebImportError.conversion }
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = .nonPersistent()
                configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
                let view = WKWebView(frame: .zero, configuration: configuration)
                view.navigationDelegate = self
                self.view = view
                view.loadFileURL(directory.appendingPathComponent("index.html"), allowingReadAccessTo: directory)
                timeout = Task { [weak self, weak view] in
                    do { try await Task.sleep(for: .seconds(10)) } catch { return }
                    guard let self, let view, self.view === view else { return }
                    self.finish(.failure(WebImportError.conversion))
                }
                self.arguments = ["html": page.html, "baseURL": page.baseURL?.absoluteString ?? "", "extract": page.extractArticle]
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    private var arguments: [String: Any] = [:]

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard view === webView else { return }
        webView.callAsyncJavaScript("return window.bakerWebImport(html, baseURL, extract);",
                                    arguments: arguments, in: nil, in: .page) { [weak self, weak webView] result in
            guard let self, let webView, self.view === webView else { return }
            guard case let .success(value) = result, let output = value as? [String: String],
                  let title = output["title"], let printText = output["printText"] else {
                self.finish(.failure(WebImportError.conversion))
                return
            }
            guard !printText.isEmpty else { self.finish(.failure(WebImportError.empty)); return }
            guard printText.utf8.count <= WebImportSource.limit else {
                self.finish(.failure(WebImportError.tooLarge)); return
            }
            self.finish(.success(WebImportDocument(title: title, printText: printText)))
        }
        arguments = [:]
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let index = directory?.appendingPathComponent("index.html")
        decisionHandler(action.targetFrame?.isMainFrame == true && action.request.url == index ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if view === webView { finish(.failure(WebImportError.conversion)) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if view === webView { finish(.failure(WebImportError.conversion)) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if view === webView { finish(.failure(WebImportError.conversion)) }
    }

    private func finish(_ result: Result<WebImportDocument, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        arguments = [:]
        view?.navigationDelegate = nil
        view?.stopLoading()
        view = nil
        continuation.resume(with: result)
    }
}
