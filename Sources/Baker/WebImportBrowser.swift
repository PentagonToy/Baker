import SwiftUI
import WebKit

/// Owns only a temporary download. Files can retain it until the queue is cleared.
final class WebImportDownloadedPDF {
    let url: URL
    private let directory: URL

    init(suggestedFilename: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("baker-web-" + UUID().uuidString)
        let stem = (URL(fileURLWithPath: suggestedFilename).deletingPathExtension().lastPathComponent)
            .components(separatedBy: CharacterSet(charactersIn: "/:").union(.controlCharacters))
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = stem.isEmpty || stem.hasPrefix(".") ? "Web Document" : String(stem.prefix(80))
        url = directory.appendingPathComponent(name).appendingPathExtension("pdf")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
final class WebImportBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    @Published private(set) var origin = ""
    @Published private(set) var message = ""
    @Published private(set) var loading = true
    @Published private(set) var canUsePage = false
    @Published private(set) var canGoBack = false
    @Published private(set) var downloading = false
    @Published private(set) var pdf: WebImportDownloadedPDF?

    let initialURL: URL
    let webView: WKWebView
    private let validateURL: @Sendable (URL) throws -> Void
    private var navigation: WKNavigation?
    private var readableResponse = false
    private var activeDownload: WKDownload?
    private var pendingPDF: WebImportDownloadedPDF?
    private var monitor: Task<Void, Never>?
    private var verificationWait: Task<Void, Never>?
    private var verificationDelayed = false
    private var closed = false
    private static let downloadLimit = 64 * 1_024 * 1_024

    init(url: URL, validateURL: @escaping @Sendable (URL) throws -> Void = { try WebImportSource.validatePublicURL($0) }) {
        initialURL = url
        self.validateURL = validateURL
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        origin = Self.displayOrigin(url)
        webView.load(URLRequest(url: url))
    }

    func open(_ address: String) {
        let input = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: input), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
            message = WebImportError.invalidURL.localizedDescription
            return
        }
        webView.load(URLRequest(url: url))
    }

    func reload() {
        if webView.url == nil { webView.load(URLRequest(url: initialURL)) }
        else { webView.reload() }
    }

    func close() {
        closed = true
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        endVerification()
        stopDownload()
    }

    func page() async throws -> WebImportSource {
        guard !closed, canUsePage, let url = webView.url,
              var base = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw WebImportError.empty
        }
        let previousNavigation = navigation
        // Collect content only on explicit import. Form values and scripts never cross the bridge.
        let result = try await webView.callAsyncJavaScript("""
            const root = document.querySelector("main, article") || document.body;
            if (!root || Array.from(document.querySelectorAll('input[type="password"]'))
                .some(field => field.getClientRects().length)) return "";
            if (root.getElementsByTagName("*").length > 50000) return null;
            const clone = root.cloneNode(true);
            clone.querySelectorAll("form,input,textarea,select,script,iframe,template,[hidden]").forEach(node => node.remove());
            const html = clone.outerHTML;
            return html.length <= limit ? html : null;
            """, arguments: ["limit": WebImportSource.limit], in: nil, contentWorld: .defaultClient)
        try Task.checkCancellation()
        guard !closed, canUsePage, navigation === previousNavigation, webView.url == url else {
            throw WebImportError.empty
        }
        guard let html = result as? String else { throw WebImportError.tooLarge }
        guard !html.isEmpty else { throw WebImportError.empty }
        base.query = nil
        base.fragment = nil
        return .html(html, baseURL: base.url)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard !closed, let url = action.request.url else { return .cancel }
        let mainFrame = action.targetFrame?.isMainFrame != false
        // Turnstile uses local iframe documents. Keep top-level and network policy intact.
        if !mainFrame, Self.isLocalFrameDocument(url) { return .allow }
        if permitsBlob(url) { return action.shouldPerformDownload ? .download : .allow }
        guard await permits(url, showError: mainFrame) else { return .cancel }
        return action.shouldPerformDownload ? .download : .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard let http = response.response as? HTTPURLResponse else {
            if Self.isPDFResponse(response.response, filename: response.response.suggestedFilename),
               let url = response.response.url, permitsBlob(url) { return .download }
            return response.isForMainFrame ? .cancel : .allow
        }
        if (200..<300).contains(http.statusCode), Self.isPDFResponse(http, filename: http.suggestedFilename) {
            endVerification()
            return .download
        }
        guard response.isForMainFrame else { return .allow }
        let requiresBrowser = WebImportSource.requiresBrowser(http)
        if requiresBrowser {
            showVerification()
        } else {
            endVerification()
        }
        readableResponse = (200..<300).contains(http.statusCode) && !requiresBrowser
            && ["text/html", "application/xhtml+xml"].contains(http.mimeType ?? "")
        return response.canShowMIMEType ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.targetFrame == nil { webView.load(action.request) }
        return nil
    }

    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        .deny
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        self.navigation = navigation
        loading = true
        canUsePage = false
        readableResponse = false
        pdf = nil
        message = ""
        stopDownload()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let url = webView.url { origin = Self.displayOrigin(url) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.navigation === navigation else { return }
        loading = false
        canUsePage = readableResponse && !downloading
        canGoBack = webView.canGoBack
        if let url = webView.url { origin = Self.displayOrigin(url) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationFailed(navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationFailed(navigation, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        endVerification()
        loading = false
        canUsePage = false
        message = "The page closed unexpectedly. Reload to continue."
    }

    private func navigationFailed(_ navigation: WKNavigation?, error: Error) {
        guard self.navigation === navigation else { return }
        loading = false
        canGoBack = webView.canGoBack
        if !downloading, message.isEmpty, (error as NSError).code != NSURLErrorCancelled {
            message = "Baker couldn’t open this page here. Reload or open it in your browser."
        }
    }

    private static let verificationHint = "Verification is taking longer. Reload to retry, or use your browser and add the downloaded PDF to Baker."

    private func showVerification() {
        message = verificationDelayed ? Self.verificationHint : "Complete the site’s sign-in or security check, then select the page."
        guard verificationWait == nil else { return }
        verificationWait = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self else { return }
            self.verificationDelayed = true
            self.message = Self.verificationHint
        }
    }

    private func endVerification() {
        verificationWait?.cancel()
        verificationWait = nil
        verificationDelayed = false
    }

    static func isLocalFrameDocument(_ url: URL) -> Bool {
        ["about:blank", "about:srcdoc"].contains(url.absoluteString)
    }

    private func permits(_ url: URL, showError: Bool) async -> Bool {
        let host = url.host(percentEncoded: false)?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if host == "accounts.google.com" {
            if showError {
                message = "Google sign-in needs your browser. Open the original link there to continue."
                loading = false
            }
            return false
        }
        let validateURL = validateURL
        let allowed = await Task.detached(priority: .userInitiated) { (try? validateURL(url)) != nil }.value
        guard !closed else { return false }
        if !allowed, showError {
            message = "Baker couldn’t open this address. Enter a public HTTP or HTTPS link."
            loading = false
        }
        return allowed
    }

    private func permitsBlob(_ url: URL) -> Bool {
        guard url.scheme == "blob", let embeddedOrigin = URL(string: String(url.absoluteString.dropFirst(5))),
              let current = webView.url, ["http", "https"].contains(embeddedOrigin.scheme ?? "") else { return false }
        return Self.displayOrigin(embeddedOrigin) == Self.displayOrigin(current)
    }

    private static func displayOrigin(_ url: URL) -> String {
        guard let scheme = url.scheme, let host = url.host(percentEncoded: true) else { return "" }
        return scheme + "://" + host + (url.port.map { ":\($0)" } ?? "")
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        beginDownload(download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        beginDownload(download)
    }

    private static func isPDFResponse(_ response: URLResponse, filename: String?) -> Bool {
        response.mimeType == "application/pdf"
            || (response.mimeType == "application/octet-stream" && filename?.lowercased().hasSuffix(".pdf") == true)
    }

    private func beginDownload(_ download: WKDownload) {
        guard !closed, activeDownload == nil else { download.cancel(nil); return }
        loading = false
        canUsePage = false
        downloading = true
        message = ""
        pdf = nil
        activeDownload = download
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        guard activeDownload === download, !closed else { return nil }
        guard Self.isPDFResponse(response, filename: suggestedFilename) else {
            stopDownload()
            message = "Only PDF downloads can be imported here."
            return nil
        }
        guard response.expectedContentLength <= Self.downloadLimit else {
            stopDownload()
            message = "PDF downloads support up to 64 MB."
            return nil
        }
        do {
            let file = try WebImportDownloadedPDF(suggestedFilename: suggestedFilename)
            pendingPDF = file
            monitor = Task { [weak self, weak download] in
                let clock = ContinuousClock()
                let deadline = clock.now + .seconds(120)
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                    guard let self, let download, self.activeDownload === download else { return }
                    let size = try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                    if size ?? 0 > Self.downloadLimit || clock.now >= deadline {
                        self.stopDownload()
                        self.message = "The PDF download exceeded its size or time limit."
                        return
                    }
                }
            }
            return file.url
        } catch {
            stopDownload()
            message = "Baker couldn’t create a temporary PDF file."
            return nil
        }
    }

    func download(_ download: WKDownload, decidedPolicyForHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest) async -> WKDownload.RedirectPolicy {
        guard let url = request.url, await permits(url, showError: true) else { return .cancel }
        return activeDownload === download ? .allow : .cancel
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard activeDownload === download, let file = pendingPDF else { return }
        finishDownload()
        do {
            let values = try file.url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize, size <= Self.downloadLimit else {
                message = "PDF downloads support up to 64 MB."
                return
            }
            let handle = try FileHandle(forReadingFrom: file.url)
            defer { try? handle.close() }
            let prefix = try handle.read(upToCount: 1024) ?? Data()
            guard prefix.range(of: Data("%PDF-".utf8)) != nil else {
                message = "The site didn’t return a PDF file."
                return
            }
            pdf = file
        } catch {
            message = "Baker couldn’t read the downloaded PDF."
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard activeDownload === download else { return }
        finishDownload()
        message = "The PDF download failed. Try opening it again."
    }

    private func stopDownload() {
        let file = pendingPDF
        activeDownload?.cancel { _ in withExtendedLifetime(file) {} }
        finishDownload()
    }

    private func finishDownload() {
        monitor?.cancel()
        monitor = nil
        activeDownload = nil
        pendingPDF = nil
        downloading = false
    }
}

struct WebImportBrowserSurface: NSViewRepresentable {
    let browser: WebImportBrowser
    func makeNSView(context: Context) -> WKWebView { browser.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
